#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonValue>
#include <QtCore/QProcess>
#include <QtCore/QTextStream>
#include <QtNetwork/QHostAddress>
#include <QtNetwork/QTcpServer>
#include <QtNetwork/QTcpSocket>
#include <QtGui/QMouseEvent>
#include <QtGui/QPainter>
#include <QtGui/QPainterPath>
#include <QtWidgets/QApplication>
#include <QtWidgets/QCheckBox>
#include <QtWidgets/QComboBox>
#include <QtWidgets/QFileDialog>
#include <QtWidgets/QFormLayout>
#include <QtWidgets/QGridLayout>
#include <QtWidgets/QGroupBox>
#include <QtWidgets/QHBoxLayout>
#include <QtWidgets/QLabel>
#include <QtWidgets/QLineEdit>
#include <QtWidgets/QMainWindow>
#include <QtWidgets/QMessageBox>
#include <QtWidgets/QPlainTextEdit>
#include <QtWidgets/QPushButton>
#include <QtWidgets/QSpinBox>
#include <QtWidgets/QSplitter>
#include <QtWidgets/QStatusBar>
#include <QtWidgets/QTabWidget>
#include <QtWidgets/QTreeWidget>
#include <QtWidgets/QVBoxLayout>
#include <QtWidgets/QWidget>

#include <algorithm>
#include <cstdint>
#include <limits>
#include <vector>

static uint32_t readLe32(const QByteArray &bytes, int offset)
{
    const auto *p = reinterpret_cast<const unsigned char *>(bytes.constData() + offset);
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

static QString hex64(uint64_t value)
{
    return QStringLiteral("0x%1").arg(value, 16, 16, QLatin1Char('0'));
}

static QString jsonCompact(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

static QString jsonPretty(const QJsonValue &value)
{
    return QString::fromUtf8(QJsonDocument(value.toObject()).toJson(QJsonDocument::Indented)).trimmed();
}

class WaveformWidget final : public QWidget
{
public:
    explicit WaveformWidget(QWidget *parent = nullptr) : QWidget(parent)
    {
        setMouseTracking(true);
        setMinimumHeight(300);
    }

    void setSampleWords(int words)
    {
        sampleWords_ = std::max(1, words);
        decode();
        update();
    }

    void setRawBytes(const QByteArray &bytes, const QString &name)
    {
        raw_ = bytes;
        name_ = name;
        hoverSample_ = -1;
        decode();
        update();
    }

    QString hoverText() const
    {
        if (samples_.empty()) {
            return QStringLiteral("No capture loaded");
        }
        int idx = hoverSample_;
        if (idx < 0 || idx >= int(samples_.size())) {
            idx = 0;
        }
        const uint64_t v = samples_[size_t(idx)];
        return QStringLiteral("sample=%1 raw=%2 lo=%3 hi=%4")
            .arg(idx)
            .arg(hex64(v))
            .arg(QStringLiteral("0x%1").arg(uint32_t(v & 0xffffffffu), 8, 16, QLatin1Char('0')))
            .arg(QStringLiteral("0x%1").arg(uint32_t(v >> 32), 8, 16, QLatin1Char('0')));
    }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.fillRect(rect(), QColor(16, 18, 20));
        p.setRenderHint(QPainter::Antialiasing, false);

        const QRect plot = rect().adjusted(54, 34, -18, -42);
        p.setPen(QColor(80, 86, 92));
        p.drawRect(plot);
        p.setPen(QColor(120, 128, 136));
        p.drawText(14, 22, name_.isEmpty() ? QStringLiteral("RadILA Capture") : name_);

        if (samples_.empty()) {
            p.setPen(QColor(210, 214, 218));
            p.drawText(plot, Qt::AlignCenter, QStringLiteral("Open a .bin capture or listen for a capture stream"));
            return;
        }

        const int lanes = 8;
        const int rowH = std::max(18, plot.height() / lanes);
        const int n = int(samples_.size());
        for (int lane = 0; lane < lanes; ++lane) {
            const int yMid = plot.top() + lane * rowH + rowH / 2;
            p.setPen(QColor(45, 50, 55));
            p.drawLine(plot.left(), yMid, plot.right(), yMid);
            p.setPen(QColor(150, 156, 162));
            p.drawText(8, yMid + 4, QStringLiteral("b%1").arg(lane));
        }

        const auto xFor = [&](int i) {
            if (n <= 1) {
                return plot.left();
            }
            return plot.left() + int((double(i) / double(n - 1)) * double(plot.width()));
        };

        for (int lane = 0; lane < lanes; ++lane) {
            QPainterPath path;
            bool have = false;
            const int base = plot.top() + lane * rowH + rowH - 4;
            const int high = plot.top() + lane * rowH + 4;
            for (int i = 0; i < n; ++i) {
                const bool bit = ((samples_[size_t(i)] >> lane) & 1u) != 0;
                const int x = xFor(i);
                const int y = bit ? high : base;
                if (!have) {
                    path.moveTo(x, y);
                    have = true;
                } else {
                    path.lineTo(x, y);
                }
            }
            p.setPen(QPen(QColor(67, 166, 198), 1.4));
            p.drawPath(path);
        }

        if (hoverSample_ >= 0 && hoverSample_ < n) {
            const int x = xFor(hoverSample_);
            p.setPen(QPen(QColor(240, 196, 82), 1));
            p.drawLine(x, plot.top(), x, plot.bottom());
            p.fillRect(QRect(plot.left(), plot.bottom() + 8, plot.width(), 24), QColor(26, 29, 32));
            p.setPen(QColor(232, 234, 236));
            p.drawText(plot.left() + 8, plot.bottom() + 25, hoverText());
        }
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        if (samples_.empty()) {
            return;
        }
        const QRect plot = rect().adjusted(54, 34, -18, -42);
        const double t = std::clamp(double(event->pos().x() - plot.left()) / std::max(1, plot.width()), 0.0, 1.0);
        hoverSample_ = int(t * double(samples_.size() - 1));
        setToolTip(hoverText());
        update();
    }

private:
    void decode()
    {
        samples_.clear();
        const int stride = sampleWords_ * 4;
        if (stride <= 0) {
            return;
        }
        for (int off = 0; off + stride <= raw_.size(); off += stride) {
            uint64_t value = readLe32(raw_, off);
            if (sampleWords_ > 1) {
                value |= uint64_t(readLe32(raw_, off + 4)) << 32;
            }
            samples_.push_back(value);
        }
    }

    QByteArray raw_;
    QString name_;
    int sampleWords_ = 2;
    int hoverSample_ = -1;
    std::vector<uint64_t> samples_;
};

class MainWindow final : public QMainWindow
{
public:
    MainWindow()
    {
        auto *central = new QWidget(this);
        auto *root = new QVBoxLayout(central);

        auto *splitter = new QSplitter(Qt::Horizontal, this);
        auto *left = new QWidget(this);
        auto *leftLayout = new QVBoxLayout(left);
        auto *tabs = new QTabWidget(this);

        tabs->addTab(buildDaemonTab(), QStringLiteral("Target"));
        tabs->addTab(buildRadbuildTab(), QStringLiteral("RadBuild"));
        tabs->addTab(buildIlaTab(), QStringLiteral("RadILA"));
        tabs->addTab(buildCaptureTab(), QStringLiteral("Capture"));
        leftLayout->addWidget(tabs);

        waveform_ = new WaveformWidget(this);
        log_ = new QPlainTextEdit(this);
        log_->setReadOnly(true);
        log_->setMaximumBlockCount(700);
        log_->setMaximumHeight(160);

        auto *right = new QWidget(this);
        auto *rightLayout = new QVBoxLayout(right);
        rightLayout->addWidget(waveform_, 1);
        rightLayout->addWidget(log_);

        splitter->addWidget(left);
        splitter->addWidget(right);
        splitter->setStretchFactor(0, 0);
        splitter->setStretchFactor(1, 1);
        splitter->setSizes({420, 820});
        root->addWidget(splitter);
        setCentralWidget(central);
        resize(1280, 790);
        setWindowTitle(QStringLiteral("RadFPGA Debug Hub"));

        connect(&server_, &QTcpServer::newConnection, this, [this]() { acceptConnection(); });
        connect(sampleWords_, qOverload<int>(&QSpinBox::valueChanged), this, [this](int v) {
            waveform_->setSampleWords(v);
        });
    }

private:
    QWidget *buildDaemonTab()
    {
        auto *page = new QWidget(this);
        auto *layout = new QGridLayout(page);
        daemonHost_ = new QLineEdit(QStringLiteral("127.0.0.1"), this);
        daemonPort_ = new QSpinBox(this);
        daemonPort_->setRange(1, 65535);
        daemonPort_->setValue(9737);
        transport_ = new QComboBox(this);
        transport_->addItems({
            QStringLiteral("AXI/LitePCIe"),
            QStringLiteral("Ethernet/PetaLinux"),
            QStringLiteral("SPI"),
            QStringLiteral("I2C"),
            QStringLiteral("UART Bridge")
        });
        auto *startBtn = new QPushButton(QStringLiteral("Start daemon"), this);
        auto *pingBtn = new QPushButton(QStringLiteral("Ping"), this);
        auto *transportBtn = new QPushButton(QStringLiteral("Transport status"), this);
        layout->addWidget(new QLabel(QStringLiteral("Daemon host")), 0, 0);
        layout->addWidget(daemonHost_, 0, 1);
        layout->addWidget(new QLabel(QStringLiteral("Port")), 1, 0);
        layout->addWidget(daemonPort_, 1, 1);
        layout->addWidget(new QLabel(QStringLiteral("Transport")), 2, 0);
        layout->addWidget(transport_, 2, 1);
        layout->addWidget(startBtn, 3, 0);
        layout->addWidget(pingBtn, 3, 1);
        layout->addWidget(transportBtn, 4, 0, 1, 2);
        layout->setRowStretch(5, 1);

        connect(startBtn, &QPushButton::clicked, this, [this]() { startDaemon(); });
        connect(pingBtn, &QPushButton::clicked, this, [this]() {
            logResponse(QStringLiteral("daemon ping"), requestDaemon({{"method", "ping"}}));
        });
        connect(transportBtn, &QPushButton::clicked, this, [this]() {
            logResponse(QStringLiteral("transport status"), requestDaemon({
                {"method", "transport_status"},
                {"transport", transport_->currentText()}
            }));
        });
        return page;
    }

    QWidget *buildRadbuildTab()
    {
        auto *page = new QWidget(this);
        auto *layout = new QGridLayout(page);
        radServer_ = new QLineEdit(QStringLiteral("https://127.0.0.1:8767"), this);
        radToken_ = new QLineEdit(this);
        radToken_->setEchoMode(QLineEdit::Password);
        radUser_ = new QLineEdit(QStringLiteral("admin"), this);
        radPassword_ = new QLineEdit(this);
        radPassword_->setEchoMode(QLineEdit::Password);
        radProject_ = new QComboBox(this);
        radProject_->setMinimumContentsLength(24);
        auto *discoverBtn = new QPushButton(QStringLiteral("Discover"), this);
        auto *statusBtn = new QPushButton(QStringLiteral("Status"), this);
        auto *loginBtn = new QPushButton(QStringLiteral("Login token"), this);
        auto *projectsBtn = new QPushButton(QStringLiteral("Projects"), this);
        auto *clientsBtn = new QPushButton(QStringLiteral("Clients"), this);
        auto *taskBtn = new QPushButton(QStringLiteral("Queue build task"), this);

        layout->addWidget(new QLabel(QStringLiteral("Server")), 0, 0);
        layout->addWidget(radServer_, 0, 1, 1, 2);
        layout->addWidget(new QLabel(QStringLiteral("API token")), 1, 0);
        layout->addWidget(radToken_, 1, 1, 1, 2);
        layout->addWidget(new QLabel(QStringLiteral("Username")), 2, 0);
        layout->addWidget(radUser_, 2, 1, 1, 2);
        layout->addWidget(new QLabel(QStringLiteral("Password")), 3, 0);
        layout->addWidget(radPassword_, 3, 1, 1, 2);
        layout->addWidget(new QLabel(QStringLiteral("Project")), 4, 0);
        layout->addWidget(radProject_, 4, 1, 1, 2);
        layout->addWidget(discoverBtn, 5, 0);
        layout->addWidget(statusBtn, 5, 1);
        layout->addWidget(loginBtn, 5, 2);
        layout->addWidget(projectsBtn, 6, 0);
        layout->addWidget(clientsBtn, 6, 1);
        layout->addWidget(taskBtn, 6, 2);
        layout->setRowStretch(7, 1);

        connect(discoverBtn, &QPushButton::clicked, this, [this]() {
            logResponse(QStringLiteral("radbuild discover"), requestDaemon({{"method", "radbuild_discover"}}));
        });
        connect(statusBtn, &QPushButton::clicked, this, [this]() {
            auto response = radbuildRequest(QStringLiteral("radbuild_status"));
            if (response.value(QStringLiteral("local_token")).toBool() && radToken_->text().isEmpty()) {
                radToken_->setText(response.value(QStringLiteral("token_hint")).toString());
            }
            logResponse(QStringLiteral("radbuild status"), response);
        });
        connect(loginBtn, &QPushButton::clicked, this, [this]() {
            auto response = requestDaemon({
                {"method", "radbuild_login"},
                {"server", radServer_->text()},
                {"username", radUser_->text()},
                {"password", radPassword_->text()}
            });
            const QString token = response.value(QStringLiteral("api_token")).toString();
            if (!token.isEmpty()) {
                radToken_->setText(token);
            }
            logResponse(QStringLiteral("radbuild login token"), response);
        });
        connect(projectsBtn, &QPushButton::clicked, this, [this]() {
            auto response = radbuildRequest(QStringLiteral("radbuild_projects"));
            updateProjects(response.value(QStringLiteral("projects")).toArray());
            logResponse(QStringLiteral("radbuild projects"), response);
        });
        connect(clientsBtn, &QPushButton::clicked, this, [this]() {
            logResponse(QStringLiteral("radbuild clients"), radbuildRequest(QStringLiteral("radbuild_clients")));
        });
        connect(taskBtn, &QPushButton::clicked, this, [this]() { queueBuildTask(); });
        return page;
    }

    QWidget *buildIlaTab()
    {
        auto *page = new QWidget(this);
        auto *layout = new QGridLayout(page);
        signalMap_ = new QLineEdit(this);
        ilaCore_ = new QComboBox(this);
        triggerMask_ = new QLineEdit(QStringLiteral("0x00000000"), this);
        triggerValue_ = new QLineEdit(QStringLiteral("0x00000001"), this);
        words_ = new QSpinBox(this);
        words_->setRange(16, 1048576);
        words_->setValue(1024);
        post_ = new QSpinBox(this);
        post_->setRange(0, 1048575);
        post_->setValue(511);
        signalTree_ = new QTreeWidget(this);
        signalTree_->setHeaderLabels({QStringLiteral("Signal"), QStringLiteral("Width")});
        auto *browseBtn = new QPushButton(QStringLiteral("Open map"), this);
        auto *loadBtn = new QPushButton(QStringLiteral("Load"), this);
        auto *armBtn = new QPushButton(QStringLiteral("Arm"), this);
        auto *readBtn = new QPushButton(QStringLiteral("Read capture"), this);

        layout->addWidget(new QLabel(QStringLiteral("Signal map")), 0, 0);
        layout->addWidget(signalMap_, 0, 1);
        layout->addWidget(browseBtn, 0, 2);
        layout->addWidget(loadBtn, 0, 3);
        layout->addWidget(new QLabel(QStringLiteral("Core")), 1, 0);
        layout->addWidget(ilaCore_, 1, 1, 1, 3);
        layout->addWidget(new QLabel(QStringLiteral("Mask")), 2, 0);
        layout->addWidget(triggerMask_, 2, 1);
        layout->addWidget(new QLabel(QStringLiteral("Value")), 2, 2);
        layout->addWidget(triggerValue_, 2, 3);
        layout->addWidget(new QLabel(QStringLiteral("Words")), 3, 0);
        layout->addWidget(words_, 3, 1);
        layout->addWidget(new QLabel(QStringLiteral("Post")), 3, 2);
        layout->addWidget(post_, 3, 3);
        layout->addWidget(armBtn, 4, 0, 1, 2);
        layout->addWidget(readBtn, 4, 2, 1, 2);
        layout->addWidget(signalTree_, 5, 0, 1, 4);
        layout->setRowStretch(5, 1);

        connect(browseBtn, &QPushButton::clicked, this, [this]() {
            const QString path = QFileDialog::getOpenFileName(this, QStringLiteral("Open RadILA signal map"), QString(), QStringLiteral("Signal maps (*.json *.txt *.map);;All files (*)"));
            if (!path.isEmpty()) {
                signalMap_->setText(path);
            }
        });
        connect(loadBtn, &QPushButton::clicked, this, [this]() { loadSignalMap(); });
        connect(armBtn, &QPushButton::clicked, this, [this]() { triggerIla(false); });
        connect(readBtn, &QPushButton::clicked, this, [this]() { triggerIla(true); });
        connect(ilaCore_, qOverload<int>(&QComboBox::currentIndexChanged), this, [this]() { updateSignalTreeForCurrentCore(); });
        return page;
    }

    QWidget *buildCaptureTab()
    {
        auto *page = new QWidget(this);
        auto *layout = new QGridLayout(page);
        capturePort_ = new QSpinBox(this);
        capturePort_->setRange(1, 65535);
        capturePort_->setValue(9001);
        sampleWords_ = new QSpinBox(this);
        sampleWords_->setRange(1, 4);
        sampleWords_->setValue(2);
        captureDir_ = new QLineEdit(QStringLiteral("/tmp/radfpga-debug-captures"), this);
        boardIp_ = new QLineEdit(QStringLiteral("192.168.2.75"), this);
        hostIp_ = new QLineEdit(QStringLiteral("192.168.2.10"), this);
        timeoutMs_ = new QSpinBox(this);
        timeoutMs_->setRange(100, 300000);
        timeoutMs_->setValue(60000);
        live_ = new QCheckBox(QStringLiteral("Valid edge trigger"), this);
        live_->setChecked(true);
        auto *listenBtn = new QPushButton(QStringLiteral("Listen"), this);
        auto *openBtn = new QPushButton(QStringLiteral("Open .bin"), this);
        auto *sshBtn = new QPushButton(QStringLiteral("SSH capture"), this);

        layout->addWidget(new QLabel(QStringLiteral("Port")), 0, 0);
        layout->addWidget(capturePort_, 0, 1);
        layout->addWidget(new QLabel(QStringLiteral("Sample words")), 0, 2);
        layout->addWidget(sampleWords_, 0, 3);
        layout->addWidget(new QLabel(QStringLiteral("Capture dir")), 1, 0);
        layout->addWidget(captureDir_, 1, 1, 1, 3);
        layout->addWidget(listenBtn, 2, 0);
        layout->addWidget(openBtn, 2, 1);
        layout->addWidget(new QLabel(QStringLiteral("Board IP")), 3, 0);
        layout->addWidget(boardIp_, 3, 1);
        layout->addWidget(new QLabel(QStringLiteral("Host IP")), 3, 2);
        layout->addWidget(hostIp_, 3, 3);
        layout->addWidget(new QLabel(QStringLiteral("Timeout ms")), 4, 0);
        layout->addWidget(timeoutMs_, 4, 1);
        layout->addWidget(live_, 4, 2);
        layout->addWidget(sshBtn, 4, 3);
        layout->setRowStretch(5, 1);

        connect(listenBtn, &QPushButton::clicked, this, [this, listenBtn]() {
            if (server_.isListening()) {
                server_.close();
                listenBtn->setText(QStringLiteral("Listen"));
                statusBar()->showMessage(QStringLiteral("TCP listener stopped"));
                return;
            }
            startListening();
            listenBtn->setText(QStringLiteral("Stop"));
        });
        connect(openBtn, &QPushButton::clicked, this, [this]() { openCapture(); });
        connect(sshBtn, &QPushButton::clicked, this, [this]() { triggerBoardOverSsh(); });
        return page;
    }

    void appendLog(const QString &msg)
    {
        log_->appendPlainText(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss ")) + msg);
    }

    QJsonObject requestDaemon(const QJsonObject &request, int timeoutMs = 6000)
    {
        QTcpSocket socket;
        socket.connectToHost(daemonHost_->text(), quint16(daemonPort_->value()));
        if (!socket.waitForConnected(timeoutMs)) {
            return {{"ok", false}, {"error", socket.errorString()}};
        }
        const QByteArray line = QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n';
        socket.write(line);
        if (!socket.waitForBytesWritten(timeoutMs)) {
            return {{"ok", false}, {"error", socket.errorString()}};
        }
        QByteArray response;
        while (!response.contains('\n')) {
            if (!socket.waitForReadyRead(timeoutMs)) {
                return {{"ok", false}, {"error", socket.errorString()}};
            }
            response += socket.readAll();
        }
        const auto doc = QJsonDocument::fromJson(response.left(response.indexOf('\n')));
        if (!doc.isObject()) {
            return {{"ok", false}, {"error", "daemon returned non-JSON response"}};
        }
        return doc.object();
    }

    QJsonObject radbuildRequest(const QString &method)
    {
        return requestDaemon({
            {"method", method},
            {"server", radServer_->text()},
            {"token", radToken_->text()}
        }, 10000);
    }

    void logResponse(const QString &label, const QJsonObject &response)
    {
        QJsonObject safe = response;
        if (safe.contains(QStringLiteral("api_token"))) {
            safe.insert(QStringLiteral("api_token"), QStringLiteral("<hidden>"));
        }
        if (safe.contains(QStringLiteral("token_hint"))) {
            safe.insert(QStringLiteral("token_hint"), QStringLiteral("<hidden>"));
        }
        if (!response.value(QStringLiteral("ok")).toBool()) {
            statusBar()->showMessage(response.value(QStringLiteral("error")).toString(QStringLiteral("request failed")));
        } else {
            statusBar()->showMessage(label + QStringLiteral(" ok"));
        }
        appendLog(label + QStringLiteral(": ") + QString::fromUtf8(QJsonDocument(safe).toJson(QJsonDocument::Compact)));
    }

    void startDaemon()
    {
        if (daemonProcess_ && daemonProcess_->state() != QProcess::NotRunning) {
            appendLog(QStringLiteral("Daemon already running"));
            return;
        }
        auto *proc = new QProcess(this);
        daemonProcess_ = proc;
        const QString exe = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("radfpga_debug_hubd"));
        connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc]() {
            const QString text = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
            if (!text.isEmpty()) {
                appendLog(QStringLiteral("daemon: ") + text);
            }
        });
        connect(proc, &QProcess::readyReadStandardError, this, [this, proc]() {
            const QString text = QString::fromUtf8(proc->readAllStandardError()).trimmed();
            if (!text.isEmpty()) {
                appendLog(QStringLiteral("daemon stderr: ") + text);
            }
        });
        connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this, proc](int code, QProcess::ExitStatus) {
            appendLog(QStringLiteral("Daemon exited with code %1").arg(code));
            if (daemonProcess_ == proc) {
                daemonProcess_ = nullptr;
            }
            proc->deleteLater();
        });
        proc->start(exe, {QStringLiteral("--host"), daemonHost_->text(), QStringLiteral("--port"), QString::number(daemonPort_->value())});
        if (!proc->waitForStarted(2000)) {
            QMessageBox::warning(this, QStringLiteral("Daemon start failed"), proc->errorString());
            proc->deleteLater();
            daemonProcess_ = nullptr;
            return;
        }
        appendLog(QStringLiteral("Started %1").arg(exe));
    }

    void updateProjects(const QJsonArray &projects)
    {
        radProject_->clear();
        for (const auto &value : projects) {
            const QJsonObject project = value.toObject();
            const QString name = project.value(QStringLiteral("name")).toString();
            const QString path = project.value(QStringLiteral("path")).toString();
            radProject_->addItem(name.isEmpty() ? path : name, project);
        }
    }

    void queueBuildTask()
    {
        const QJsonObject project = radProject_->currentData().toJsonObject();
        const QString path = project.value(QStringLiteral("path")).toString();
        const QString name = project.value(QStringLiteral("name")).toString(QStringLiteral("RadFPGA Debug Hub build"));
        const QJsonObject response = requestDaemon({
            {"method", "radbuild_queue_build"},
            {"server", radServer_->text()},
            {"token", radToken_->text()},
            {"title", QStringLiteral("RadFPGA Debug Hub build: ") + name},
            {"objective", QStringLiteral("Build and verify FPGA design from RadFPGA Debug Hub.")},
            {"project_path", path},
            {"command", QStringLiteral("build_vivado")},
            {"assigned_machine", QStringLiteral("local")}
        }, 10000);
        logResponse(QStringLiteral("radbuild queue build"), response);
    }

    void loadSignalMap()
    {
        const QJsonObject response = requestDaemon({
            {"method", "load_signal_map"},
            {"path", signalMap_->text()}
        }, 10000);
        if (response.value(QStringLiteral("ok")).toBool()) {
            cores_ = response.value(QStringLiteral("cores")).toArray();
            ilaCore_->clear();
            for (const auto &value : cores_) {
                const QJsonObject core = value.toObject();
                ilaCore_->addItem(core.value(QStringLiteral("name")).toString(QStringLiteral("RadILA")), core);
            }
            updateSignalTreeForCurrentCore();
        }
        logResponse(QStringLiteral("load signal map"), response);
    }

    void updateSignalTreeForCurrentCore()
    {
        signalTree_->clear();
        const QJsonObject core = ilaCore_->currentData().toJsonObject();
        const QJsonArray signalList = core.value(QStringLiteral("signals")).toArray();
        for (const auto &value : signalList) {
            const QJsonObject signal = value.toObject();
            auto *item = new QTreeWidgetItem(signalTree_);
            item->setText(0, signal.value(QStringLiteral("name")).toString());
            item->setText(1, QString::number(signal.value(QStringLiteral("width")).toInt()));
        }
        signalTree_->resizeColumnToContents(0);
    }

    void triggerIla(bool readCapture)
    {
        const QJsonObject response = requestDaemon({
            {"method", "ila_command"},
            {"transport", transport_->currentText()},
            {"core", ilaCore_->currentText()},
            {"mask", triggerMask_->text()},
            {"value", triggerValue_->text()},
            {"words", words_->value()},
            {"post", post_->value()},
            {"read_capture", readCapture}
        }, 10000);
        logResponse(readCapture ? QStringLiteral("read capture") : QStringLiteral("arm ila"), response);
    }

    void startListening()
    {
        QDir().mkpath(captureDir_->text());
        if (!server_.listen(QHostAddress::Any, quint16(capturePort_->value()))) {
            QMessageBox::warning(this, QStringLiteral("Listen failed"), server_.errorString());
            return;
        }
        appendLog(QStringLiteral("Listening on 0.0.0.0:%1").arg(capturePort_->value()));
        statusBar()->showMessage(QStringLiteral("Listening for capture stream"));
    }

    void acceptConnection()
    {
        auto *sock = server_.nextPendingConnection();
        auto *buffer = new QByteArray();
        appendLog(QStringLiteral("TCP client %1 connected").arg(sock->peerAddress().toString()));
        connect(sock, &QTcpSocket::readyRead, this, [sock, buffer]() {
            buffer->append(sock->readAll());
        });
        connect(sock, &QTcpSocket::disconnected, this, [this, sock, buffer]() {
            const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
            const QString path = QDir(captureDir_->text()).filePath(QStringLiteral("capture-%1.bin").arg(stamp));
            QFile f(path);
            if (f.open(QIODevice::WriteOnly)) {
                f.write(*buffer);
                f.close();
                waveform_->setSampleWords(sampleWords_->value());
                waveform_->setRawBytes(*buffer, QFileInfo(path).fileName());
                appendLog(QStringLiteral("Received %1 bytes -> %2").arg(buffer->size()).arg(path));
                statusBar()->showMessage(QStringLiteral("Loaded %1").arg(path));
            } else {
                appendLog(QStringLiteral("Could not save %1").arg(path));
            }
            delete buffer;
            sock->deleteLater();
        });
    }

    void openCapture()
    {
        const QString path = QFileDialog::getOpenFileName(this, QStringLiteral("Open ILA capture"), captureDir_->text(), QStringLiteral("Binary captures (*.bin);;All files (*)"));
        if (path.isEmpty()) {
            return;
        }
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly)) {
            QMessageBox::warning(this, QStringLiteral("Open failed"), f.errorString());
            return;
        }
        const QByteArray bytes = f.readAll();
        waveform_->setSampleWords(sampleWords_->value());
        waveform_->setRawBytes(bytes, QFileInfo(path).fileName());
        appendLog(QStringLiteral("Opened %1 bytes from %2").arg(bytes.size()).arg(path));
    }

    void triggerBoardOverSsh()
    {
        if (!server_.isListening()) {
            startListening();
        }
        const QString liveArg = live_->isChecked() ? QStringLiteral("--live ") : QString();
        const QString remote = QStringLiteral(
            "sudo -n /usr/bin/radila-capture --status %1--words %2 --post %3 --timeout-ms %4 --out /tmp/radfpga-debug-capture.bin --send %5 %6")
            .arg(liveArg)
            .arg(words_->value())
            .arg(post_->value())
            .arg(timeoutMs_->value())
            .arg(hostIp_->text())
            .arg(capturePort_->value());
        const QStringList args = {
            QStringLiteral("-o"), QStringLiteral("StrictHostKeyChecking=no"),
            QStringLiteral("petalinux@") + boardIp_->text(),
            remote
        };
        appendLog(QStringLiteral("Running ssh capture trigger on %1").arg(boardIp_->text()));
        auto *proc = new QProcess(this);
        connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc]() {
            const QString text = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
            if (!text.isEmpty()) {
                appendLog(text);
            }
        });
        connect(proc, &QProcess::readyReadStandardError, this, [this, proc]() {
            const QString text = QString::fromUtf8(proc->readAllStandardError()).trimmed();
            if (!text.isEmpty()) {
                appendLog(text);
            }
        });
        connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this, proc](int code, QProcess::ExitStatus) {
            appendLog(QStringLiteral("ssh capture exited with code %1").arg(code));
            proc->deleteLater();
        });
        proc->start(QStringLiteral("ssh"), args);
    }

    QTcpServer server_;
    QProcess *daemonProcess_ = nullptr;
    WaveformWidget *waveform_ = nullptr;
    QPlainTextEdit *log_ = nullptr;

    QLineEdit *daemonHost_ = nullptr;
    QSpinBox *daemonPort_ = nullptr;
    QComboBox *transport_ = nullptr;

    QLineEdit *radServer_ = nullptr;
    QLineEdit *radToken_ = nullptr;
    QLineEdit *radUser_ = nullptr;
    QLineEdit *radPassword_ = nullptr;
    QComboBox *radProject_ = nullptr;

    QLineEdit *signalMap_ = nullptr;
    QComboBox *ilaCore_ = nullptr;
    QLineEdit *triggerMask_ = nullptr;
    QLineEdit *triggerValue_ = nullptr;
    QTreeWidget *signalTree_ = nullptr;
    QJsonArray cores_;

    QSpinBox *capturePort_ = nullptr;
    QSpinBox *sampleWords_ = nullptr;
    QLineEdit *captureDir_ = nullptr;
    QLineEdit *boardIp_ = nullptr;
    QLineEdit *hostIp_ = nullptr;
    QSpinBox *words_ = nullptr;
    QSpinBox *post_ = nullptr;
    QSpinBox *timeoutMs_ = nullptr;
    QCheckBox *live_ = nullptr;
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    MainWindow w;
    w.show();
    return app.exec();
}
