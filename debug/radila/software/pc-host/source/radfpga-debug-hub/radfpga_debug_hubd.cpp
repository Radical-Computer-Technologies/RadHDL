#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QEventLoop>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonValue>
#include <QtCore/QProcess>
#include <QtCore/QRegularExpression>
#include <QtCore/QStandardPaths>
#include <QtCore/QTextStream>
#include <QtCore/QUrl>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkCookie>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslError>
#include <QtNetwork/QTcpServer>
#include <QtNetwork/QTcpSocket>

#ifdef RADFPGA_HAS_SERIALPORT
#include <QtSerialPort/QSerialPortInfo>
#endif

static QString normalizeServer(QString server)
{
    server = server.trimmed();
    while (server.endsWith('/')) {
        server.chop(1);
    }
    if (!server.contains(QStringLiteral("://"))) {
        server.prepend(QStringLiteral("https://"));
    }
    return server;
}

static QJsonObject errorResponse(const QString &message)
{
    return {{"ok", false}, {"error", message}};
}

static QJsonObject okResponse(QJsonObject object = {})
{
    object.insert(QStringLiteral("ok"), true);
    return object;
}

static QString searchUpFor(const QString &start, const QString &relative)
{
    QDir dir(start);
    for (;;) {
        const QString candidate = dir.filePath(relative);
        if (QFileInfo::exists(candidate)) {
            return QFileInfo(candidate).absoluteFilePath();
        }
        if (!dir.cdUp()) {
            break;
        }
    }
    return QString();
}

static QString repoRoot()
{
    const QString cwdHit = searchUpFor(QDir::currentPath(), QStringLiteral("RadBuild/radserver/radclient.py"));
    if (!cwdHit.isEmpty()) {
        return QFileInfo(cwdHit).absoluteDir().absolutePath() + QStringLiteral("/../..");
    }
    const QString appHit = searchUpFor(QCoreApplication::applicationDirPath(), QStringLiteral("RadBuild/radserver/radclient.py"));
    if (!appHit.isEmpty()) {
        return QFileInfo(appHit).absoluteDir().absolutePath() + QStringLiteral("/../..");
    }
    return QDir::currentPath();
}

static QString radclientPath()
{
    const QString explicitPath = QString::fromLocal8Bit(qgetenv("RADBUILD_RADCLIENT"));
    if (!explicitPath.isEmpty()) {
        return explicitPath;
    }
    const QString explicitRoot = QString::fromLocal8Bit(qgetenv("RADBUILD_ROOT"));
    if (!explicitRoot.isEmpty()) {
        const QString candidate = QDir(explicitRoot).filePath(QStringLiteral("radserver/radclient.py"));
        if (QFileInfo::exists(candidate)) {
            return candidate;
        }
    }
    const QString direct = searchUpFor(QDir::currentPath(), QStringLiteral("RadBuild/radserver/radclient.py"));
    if (!direct.isEmpty()) {
        return direct;
    }
    const QString fromApp = searchUpFor(QCoreApplication::applicationDirPath(), QStringLiteral("RadBuild/radserver/radclient.py"));
    if (!fromApp.isEmpty()) {
        return fromApp;
    }
    const QString bundled = searchUpFor(QCoreApplication::applicationDirPath(), QStringLiteral("radbuild/radclient.py"));
    if (!bundled.isEmpty()) {
        return bundled;
    }
    return QStringLiteral("radclient");
}

static QString localTokenPath()
{
    const QString explicitPath = QString::fromLocal8Bit(qgetenv("RADBUILD_SERVER_CONFIG"));
    if (!explicitPath.isEmpty()) {
        return explicitPath;
    }
    const QString explicitRoot = QString::fromLocal8Bit(qgetenv("RADBUILD_ROOT"));
    if (!explicitRoot.isEmpty()) {
        const QString candidate = QDir(explicitRoot).filePath(QStringLiteral("radserver/server_config.json"));
        if (QFileInfo::exists(candidate)) {
            return candidate;
        }
    }
    const QString direct = searchUpFor(QDir::currentPath(), QStringLiteral("RadBuild/radserver/server_config.json"));
    if (!direct.isEmpty()) {
        return direct;
    }
    return searchUpFor(QCoreApplication::applicationDirPath(), QStringLiteral("RadBuild/radserver/server_config.json"));
}

static bool isLocalServer(const QString &server)
{
    const QUrl url(normalizeServer(server));
    const QString host = url.host().toLower();
    return host == QStringLiteral("127.0.0.1") || host == QStringLiteral("localhost") || host == QStringLiteral("::1");
}

static QString readLocalServerToken(const QString &server)
{
    if (!isLocalServer(server)) {
        return QString();
    }
    QFile file(localTokenPath());
    if (!file.open(QIODevice::ReadOnly)) {
        return QString();
    }
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    return doc.object().value(QStringLiteral("api_token")).toString();
}

static QString tokenForRequest(const QJsonObject &request)
{
    const QString supplied = request.value(QStringLiteral("token")).toString();
    if (!supplied.isEmpty()) {
        return supplied;
    }
    const QString envToken = QString::fromLocal8Bit(qgetenv("RADBUILD_API_TOKEN"));
    if (!envToken.isEmpty()) {
        return envToken;
    }
    return readLocalServerToken(request.value(QStringLiteral("server")).toString(QStringLiteral("https://127.0.0.1:8767")));
}

struct HttpResult {
    int status = 0;
    QJsonObject json;
    QByteArray body;
    QList<QNetworkCookie> cookies;
    QString error;
};

static HttpResult httpJson(const QString &method, const QString &server, const QString &path, const QJsonObject &payload = {}, const QString &token = {}, const QList<QNetworkCookie> &cookies = {})
{
    HttpResult result;
    QNetworkAccessManager manager;
    QNetworkRequest req(QUrl(normalizeServer(server) + path));
    req.setRawHeader("accept", "application/json");
    if (!token.isEmpty()) {
        req.setRawHeader("authorization", QByteArray("Bearer ") + token.toUtf8());
    }
    if (!cookies.isEmpty()) {
        QByteArray cookieHeader;
        for (const auto &cookie : cookies) {
            if (!cookieHeader.isEmpty()) {
                cookieHeader += "; ";
            }
            cookieHeader += cookie.name() + "=" + cookie.value();
        }
        req.setRawHeader("cookie", cookieHeader);
    }

    QNetworkReply *reply = nullptr;
    if (method == QStringLiteral("GET")) {
        reply = manager.get(req);
    } else {
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        reply = manager.post(req, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    }
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::sslErrors, reply, [reply](const QList<QSslError> &) {
        reply->ignoreSslErrors();
    });
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit, Qt::QueuedConnection);
    loop.exec();

    result.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    result.body = reply->readAll();
    result.cookies = qvariant_cast<QList<QNetworkCookie>>(reply->header(QNetworkRequest::SetCookieHeader));
    if (reply->error() != QNetworkReply::NoError) {
        result.error = reply->errorString();
    }
    const QJsonDocument doc = QJsonDocument::fromJson(result.body);
    if (doc.isObject()) {
        result.json = doc.object();
    }
    reply->deleteLater();
    return result;
}

static QJsonObject httpResponse(const HttpResult &result)
{
    if (!result.error.isEmpty()) {
        return errorResponse(result.error);
    }
    QJsonObject out = result.json;
    out.insert(QStringLiteral("ok"), result.status >= 200 && result.status < 300);
    out.insert(QStringLiteral("http_status"), result.status);
    if (result.status < 200 || result.status >= 300) {
        out.insert(QStringLiteral("error"), QString::fromUtf8(result.body));
    }
    return out;
}

static QJsonArray parseTextSignalMap(const QString &text)
{
    QJsonArray cores;
    QJsonObject core;
    core.insert(QStringLiteral("name"), QStringLiteral("RadILA"));
    QJsonArray signalList;
    const QStringList lines = text.split('\n');
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        if (line.isEmpty() || line.startsWith('#')) {
            continue;
        }
        const QStringList parts = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
        if (parts.size() < 2) {
            continue;
        }
        bool ok = false;
        const int width = parts.last().toInt(&ok);
        if (!ok) {
            continue;
        }
        signalList.append(QJsonObject{{"name", parts.first()}, {"width", width}});
    }
    core.insert(QStringLiteral("signals"), signalList);
    cores.append(core);
    return cores;
}

static QJsonArray normalizeCores(const QJsonDocument &doc, const QString &text)
{
    if (!doc.isNull()) {
        QJsonValue root;
        if (doc.isObject()) {
            const QJsonObject object = doc.object();
            if (object.value(QStringLiteral("cores")).isArray()) {
                root = object.value(QStringLiteral("cores"));
            } else if (object.value(QStringLiteral("ilas")).isArray()) {
                root = object.value(QStringLiteral("ilas"));
            } else if (object.value(QStringLiteral("name")).isString()) {
                root = QJsonArray{object};
            }
        } else if (doc.isArray()) {
            root = doc.array();
        }
        if (root.isArray()) {
            QJsonArray cores;
            for (const auto &entry : root.toArray()) {
                QJsonObject core = entry.toObject();
                if (!core.contains(QStringLiteral("signals")) && core.contains(QStringLiteral("ports"))) {
                    core.insert(QStringLiteral("signals"), core.value(QStringLiteral("ports")).toArray());
                }
                if (!core.contains(QStringLiteral("name"))) {
                    core.insert(QStringLiteral("name"), QStringLiteral("RadILA"));
                }
                cores.append(core);
            }
            return cores;
        }
    }
    return parseTextSignalMap(text);
}

class DebugHubDaemon final : public QObject
{
public:
    explicit DebugHubDaemon(QObject *parent = nullptr) : QObject(parent)
    {
        connect(&server_, &QTcpServer::newConnection, this, [this]() { acceptClient(); });
    }

    bool listen(const QString &host, quint16 port)
    {
        return server_.listen(QHostAddress(host), port);
    }

    QString errorString() const
    {
        return server_.errorString();
    }

private:
    void acceptClient()
    {
        auto *socket = server_.nextPendingConnection();
        auto *buffer = new QByteArray();
        connect(socket, &QTcpSocket::readyRead, this, [this, socket, buffer]() {
            buffer->append(socket->readAll());
            int newline = buffer->indexOf('\n');
            if (newline < 0) {
                return;
            }
            const QByteArray line = buffer->left(newline);
            const QJsonDocument doc = QJsonDocument::fromJson(line);
            const QJsonObject response = doc.isObject() ? handle(doc.object()) : errorResponse(QStringLiteral("request must be a JSON object"));
            socket->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
            socket->disconnectFromHost();
        });
        connect(socket, &QTcpSocket::disconnected, this, [socket, buffer]() {
            delete buffer;
            socket->deleteLater();
        });
    }

    QJsonObject handle(const QJsonObject &request)
    {
        const QString method = request.value(QStringLiteral("method")).toString();
        if (method == QStringLiteral("ping")) {
            return okResponse({
                {"name", "RadFPGA Debug Hub Daemon"},
                {"version", "0.1"},
                {"repo_root", QDir(repoRoot()).canonicalPath()},
                {"transports", QJsonArray{"AXI/LitePCIe", "Ethernet/PetaLinux", "SPI", "I2C", "UART Bridge"}}
            });
        }
        if (method == QStringLiteral("transport_status")) {
            QJsonArray serialPorts;
#ifdef RADFPGA_HAS_SERIALPORT
            for (const QSerialPortInfo &info : QSerialPortInfo::availablePorts()) {
                serialPorts.append(QJsonObject{
                    {"port", info.portName()},
                    {"description", info.description()},
                    {"manufacturer", info.manufacturer()}
                });
            }
#endif
            return okResponse({
                {"transport", request.value(QStringLiteral("transport")).toString()},
                {"axi_litepcie", "available through LitePCIe userspace bridge when mapped"},
                {"ethernet", "available through PetaLinux radila-capture path"},
                {"spi", "daemon frontend scaffolded; board bridge firmware required"},
                {"i2c", "daemon frontend scaffolded; board bridge firmware required"},
                {"uart_bridge", "MCU bridge framing source is included beside this tool"},
                {"serial_ports", serialPorts}
            });
        }
        if (method == QStringLiteral("radbuild_discover")) {
            return runRadclient({QStringLiteral("discover"), QStringLiteral("--timeout"), QStringLiteral("0.35")});
        }
        if (method == QStringLiteral("radbuild_status")) {
            const QString server = request.value(QStringLiteral("server")).toString(QStringLiteral("https://127.0.0.1:8767"));
            const QString token = tokenForRequest(request);
            QJsonObject out = httpResponse(httpJson(QStringLiteral("GET"), server, QStringLiteral("/api/session"), {}, token));
            if (out.value(QStringLiteral("ok")).toBool()) {
                out.insert(QStringLiteral("setup"), httpResponse(httpJson(QStringLiteral("GET"), server, QStringLiteral("/api/setup"), {}, token)));
                if (isLocalServer(server) && request.value(QStringLiteral("token")).toString().isEmpty()) {
                    out.insert(QStringLiteral("local_token"), !token.isEmpty());
                    out.insert(QStringLiteral("token_hint"), token);
                }
            }
            return out;
        }
        if (method == QStringLiteral("radbuild_projects")) {
            const QString server = request.value(QStringLiteral("server")).toString(QStringLiteral("https://127.0.0.1:8767"));
            return httpResponse(httpJson(QStringLiteral("GET"), server, QStringLiteral("/api/radbuild/projects"), {}, tokenForRequest(request)));
        }
        if (method == QStringLiteral("radbuild_clients")) {
            const QString server = request.value(QStringLiteral("server")).toString(QStringLiteral("https://127.0.0.1:8767"));
            return httpResponse(httpJson(QStringLiteral("GET"), server, QStringLiteral("/api/clients"), {}, tokenForRequest(request)));
        }
        if (method == QStringLiteral("radbuild_login")) {
            return loginRadbuild(request);
        }
        if (method == QStringLiteral("radbuild_queue_build")) {
            return queueBuildTask(request);
        }
        if (method == QStringLiteral("load_signal_map")) {
            return loadSignalMap(request);
        }
        if (method == QStringLiteral("ila_command")) {
            return okResponse({
                {"queued", true},
                {"transport", request.value(QStringLiteral("transport")).toString()},
                {"core", request.value(QStringLiteral("core")).toString()},
                {"mask", request.value(QStringLiteral("mask")).toString()},
                {"value", request.value(QStringLiteral("value")).toString()},
                {"words", request.value(QStringLiteral("words")).toInt()},
                {"post", request.value(QStringLiteral("post")).toInt()},
                {"read_capture", request.value(QStringLiteral("read_capture")).toBool()},
                {"note", "hardware transport hook is explicit here; AXI/SPI/I2C backends can share this command payload"}
            });
        }
        return errorResponse(QStringLiteral("unknown method: ") + method);
    }

    QJsonObject runRadclient(const QStringList &args)
    {
        QProcess process;
        QString program = radclientPath();
        QStringList fullArgs = args;
        if (program.endsWith(QStringLiteral(".py"))) {
            fullArgs.prepend(program);
            program = QStringLiteral("python3");
        }
        process.start(program, fullArgs);
        if (!process.waitForFinished(12000)) {
            process.kill();
            process.waitForFinished(1000);
            return errorResponse(QStringLiteral("radclient timed out"));
        }
        const QByteArray stdoutData = process.readAllStandardOutput();
        const QByteArray stderrData = process.readAllStandardError();
        const QJsonDocument doc = QJsonDocument::fromJson(stdoutData);
        QJsonObject out = doc.isObject() ? doc.object() : QJsonObject{{"stdout", QString::fromUtf8(stdoutData)}};
        out.insert(QStringLiteral("ok"), process.exitCode() == 0);
        if (process.exitCode() != 0) {
            out.insert(QStringLiteral("error"), QString::fromUtf8(stderrData).trimmed());
        }
        return out;
    }

    QJsonObject loginRadbuild(const QJsonObject &request)
    {
        const QString server = request.value(QStringLiteral("server")).toString(QStringLiteral("https://127.0.0.1:8767"));
        const QString username = request.value(QStringLiteral("username")).toString();
        const QString password = request.value(QStringLiteral("password")).toString();
        if (username.isEmpty() || password.isEmpty()) {
            return errorResponse(QStringLiteral("username and password are required for remote token authorization"));
        }
        const HttpResult login = httpJson(QStringLiteral("POST"), server, QStringLiteral("/api/login"), {
            {"username", username},
            {"password", password}
        });
        if (!login.error.isEmpty() || login.status < 200 || login.status >= 300) {
            return httpResponse(login);
        }
        const HttpResult token = httpJson(QStringLiteral("POST"), server, QStringLiteral("/api/account/token"), {}, {}, login.cookies);
        QJsonObject out = httpResponse(token);
        if (out.value(QStringLiteral("ok")).toBool()) {
            out.insert(QStringLiteral("server"), normalizeServer(server));
            out.insert(QStringLiteral("username"), username);
        }
        return out;
    }

    QJsonObject queueBuildTask(const QJsonObject &request)
    {
        const QString server = request.value(QStringLiteral("server")).toString(QStringLiteral("https://127.0.0.1:8767"));
        const QString token = tokenForRequest(request);
        if (token.isEmpty()) {
            return errorResponse(QStringLiteral("API token is required to queue a build task"));
        }
        QJsonObject metadata;
        metadata.insert(QStringLiteral("command"), request.value(QStringLiteral("command")).toString(QStringLiteral("build_vivado")));
        metadata.insert(QStringLiteral("shell"), true);
        metadata.insert(QStringLiteral("radfpga_debug_hub"), true);
        QJsonObject payload{
            {"title", request.value(QStringLiteral("title")).toString(QStringLiteral("RadFPGA Debug Hub build"))},
            {"objective", request.value(QStringLiteral("objective")).toString(QStringLiteral("Build FPGA design from RadFPGA Debug Hub."))},
            {"project_path", request.value(QStringLiteral("project_path")).toString()},
            {"assigned_machine", request.value(QStringLiteral("assigned_machine")).toString(QStringLiteral("local"))},
            {"status", "queued"},
            {"tags", QJsonArray{"radfpga-debug-hub", "build"}},
            {"metadata", metadata}
        };
        return httpResponse(httpJson(QStringLiteral("POST"), server, QStringLiteral("/api/tasks"), payload, token));
    }

    QJsonObject loadSignalMap(const QJsonObject &request)
    {
        const QString path = request.value(QStringLiteral("path")).toString();
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return errorResponse(QStringLiteral("could not open signal map: ") + file.errorString());
        }
        const QString text = QString::fromUtf8(file.readAll());
        const QJsonDocument doc = QJsonDocument::fromJson(text.toUtf8());
        const QJsonArray cores = normalizeCores(doc, text);
        return okResponse({
            {"path", QFileInfo(path).absoluteFilePath()},
            {"cores", cores},
            {"core_count", cores.size()}
        });
    }

    QTcpServer server_;
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QString host = QStringLiteral("127.0.0.1");
    quint16 port = 9737;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args[i] == QStringLiteral("--host") && i + 1 < args.size()) {
            host = args[++i];
        } else if (args[i] == QStringLiteral("--port") && i + 1 < args.size()) {
            port = quint16(args[++i].toUShort());
        }
    }

    DebugHubDaemon daemon;
    if (!daemon.listen(host, port)) {
        QTextStream(stderr) << "radfpga_debug_hubd: listen failed: " << daemon.errorString() << Qt::endl;
        return 1;
    }
    QTextStream(stdout) << "radfpga_debug_hubd listening on " << host << ":" << port << Qt::endl;
    return app.exec();
}
