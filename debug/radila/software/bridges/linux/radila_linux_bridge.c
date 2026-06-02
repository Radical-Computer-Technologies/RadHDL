#include "radila_bridge_protocol.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <linux/spi/spidev.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

typedef enum {
    BUS_SPI,
    BUS_I2C
} bridge_bus_t;

typedef struct {
    bridge_bus_t bus;
    const char *device;
    uint32_t spi_speed_hz;
    uint8_t i2c_addr;
    int tcp_port;
    bool crc;
} bridge_config_t;

typedef struct {
    int fd;
    bridge_config_t cfg;
} bridge_context_t;

static void usage(const char *prog)
{
    fprintf(stderr,
            "usage: %s --bus spi|i2c --device PATH [--serial|--tcp-port PORT] [--crc on|off]\n"
            "          [--spi-speed HZ] [--i2c-addr ADDR]\n",
            prog);
}

static int parse_args(int argc, char **argv, bridge_config_t *cfg)
{
    memset(cfg, 0, sizeof(*cfg));
    cfg->bus = BUS_SPI;
    cfg->device = "/dev/spidev0.0";
    cfg->spi_speed_hz = 10000000u;
    cfg->i2c_addr = 0x42u;
    cfg->tcp_port = 0;
    cfg->crc = true;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--bus") == 0 && i + 1 < argc) {
            const char *bus = argv[++i];
            if (strcmp(bus, "spi") == 0) {
                cfg->bus = BUS_SPI;
            } else if (strcmp(bus, "i2c") == 0) {
                cfg->bus = BUS_I2C;
                cfg->device = "/dev/i2c-1";
            } else {
                return -1;
            }
        } else if (strcmp(argv[i], "--device") == 0 && i + 1 < argc) {
            cfg->device = argv[++i];
        } else if (strcmp(argv[i], "--serial") == 0) {
            cfg->tcp_port = 0;
        } else if (strcmp(argv[i], "--tcp-port") == 0 && i + 1 < argc) {
            cfg->tcp_port = atoi(argv[++i]);
            cfg->crc = false;
        } else if (strcmp(argv[i], "--crc") == 0 && i + 1 < argc) {
            const char *mode = argv[++i];
            cfg->crc = strcmp(mode, "on") == 0 || strcmp(mode, "true") == 0 || strcmp(mode, "1") == 0;
        } else if (strcmp(argv[i], "--spi-speed") == 0 && i + 1 < argc) {
            cfg->spi_speed_hz = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--i2c-addr") == 0 && i + 1 < argc) {
            cfg->i2c_addr = (uint8_t)strtoul(argv[++i], NULL, 0);
        } else {
            return -1;
        }
    }

    return cfg->tcp_port >= 0 && cfg->device != NULL ? 0 : -1;
}

static int open_bus(bridge_context_t *ctx)
{
    ctx->fd = open(ctx->cfg.device, O_RDWR | O_CLOEXEC);
    if (ctx->fd < 0) {
        perror(ctx->cfg.device);
        return -1;
    }

    if (ctx->cfg.bus == BUS_SPI) {
        uint8_t mode = SPI_MODE_0;
        uint8_t bits = 8;
        if (ioctl(ctx->fd, SPI_IOC_WR_MODE, &mode) < 0 ||
            ioctl(ctx->fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
            ioctl(ctx->fd, SPI_IOC_WR_MAX_SPEED_HZ, &ctx->cfg.spi_speed_hz) < 0) {
            perror("spi setup");
            return -1;
        }
    } else {
        if (ioctl(ctx->fd, I2C_SLAVE, ctx->cfg.i2c_addr) < 0) {
            perror("i2c setup");
            return -1;
        }
    }

    return 0;
}

static void make_header(uint8_t *header, uint8_t op, uint32_t addr, size_t len)
{
    header[0] = op;
    header[1] = (uint8_t)(addr >> 24);
    header[2] = (uint8_t)(addr >> 16);
    header[3] = (uint8_t)(addr >> 8);
    header[4] = (uint8_t)addr;
    header[5] = (uint8_t)(len >> 8);
    header[6] = (uint8_t)len;
}

static int spi_transfer(bridge_context_t *ctx, uint8_t *tx, uint8_t *rx, size_t len)
{
    struct spi_ioc_transfer tr;
    memset(&tr, 0, sizeof(tr));
    tr.tx_buf = (uintptr_t)tx;
    tr.rx_buf = (uintptr_t)rx;
    tr.len = (uint32_t)len;
    tr.speed_hz = ctx->cfg.spi_speed_hz;
    tr.bits_per_word = 8;

    return ioctl(ctx->fd, SPI_IOC_MESSAGE(1), &tr) < 0 ? -1 : 0;
}

static int bus_read(bridge_context_t *ctx, uint32_t addr, uint8_t *data, size_t len)
{
    uint8_t header[7];
    make_header(header, 0x01u, addr, len);

    if (ctx->cfg.bus == BUS_SPI) {
        uint8_t tx[sizeof(header) + RADILA_BRIDGE_MAX_DATA];
        uint8_t rx[sizeof(header) + RADILA_BRIDGE_MAX_DATA];
        memset(tx, 0, sizeof(tx));
        memset(rx, 0, sizeof(rx));
        memcpy(tx, header, sizeof(header));
        if (spi_transfer(ctx, tx, rx, sizeof(header) + len) != 0) {
            perror("spi read");
            return -1;
        }
        memcpy(data, rx + sizeof(header), len);
        return 0;
    }

    if (write(ctx->fd, header, sizeof(header)) != (ssize_t)sizeof(header)) {
        perror("i2c read header");
        return -1;
    }
    if (read(ctx->fd, data, len) != (ssize_t)len) {
        perror("i2c read data");
        return -1;
    }
    return 0;
}

static int bus_write(bridge_context_t *ctx, uint32_t addr, const uint8_t *data, size_t len)
{
    uint8_t packet[7 + RADILA_BRIDGE_MAX_DATA];
    make_header(packet, 0x02u, addr, len);
    memcpy(packet + 7, data, len);

    if (ctx->cfg.bus == BUS_SPI) {
        uint8_t rx[sizeof(packet)];
        memset(rx, 0, sizeof(rx));
        if (spi_transfer(ctx, packet, rx, 7 + len) != 0) {
            perror("spi write");
            return -1;
        }
        return 0;
    }

    if (write(ctx->fd, packet, 7 + len) != (ssize_t)(7 + len)) {
        perror("i2c write");
        return -1;
    }
    return 0;
}

static int process_line(bridge_context_t *ctx, const char *line, char *reply, size_t reply_len)
{
    radila_bridge_cmd_t cmd;
    if (radila_bridge_parse_line(line, ctx->cfg.crc, &cmd) != 0) {
        return radila_bridge_format_error(reply, reply_len, "parse", ctx->cfg.crc);
    }

    if (cmd.op == RADILA_BRIDGE_OP_PING) {
        return radila_bridge_format_pong(reply, reply_len, ctx->cfg.crc);
    }

    if (cmd.op == RADILA_BRIDGE_OP_READ) {
        uint8_t data[RADILA_BRIDGE_MAX_DATA];
        if (bus_read(ctx, cmd.addr, data, cmd.len) != 0) {
            return radila_bridge_format_error(reply, reply_len, "read", ctx->cfg.crc);
        }
        return radila_bridge_format_read_ok(reply, reply_len, data, cmd.len, ctx->cfg.crc);
    }

    if (cmd.op == RADILA_BRIDGE_OP_WRITE) {
        if (bus_write(ctx, cmd.addr, cmd.data, cmd.len) != 0) {
            return radila_bridge_format_error(reply, reply_len, "write", ctx->cfg.crc);
        }
        return radila_bridge_format_write_ok(reply, reply_len, ctx->cfg.crc);
    }

    return radila_bridge_format_error(reply, reply_len, "op", ctx->cfg.crc);
}

static int serve_stream(bridge_context_t *ctx, FILE *in, FILE *out)
{
    char line[RADILA_BRIDGE_MAX_LINE];
    char reply[RADILA_BRIDGE_MAX_LINE];

    while (fgets(line, sizeof(line), in) != NULL) {
        if (process_line(ctx, line, reply, sizeof(reply)) < 0) {
            radila_bridge_format_error(reply, sizeof(reply), "internal", ctx->cfg.crc);
        }
        fputs(reply, out);
        fflush(out);
    }

    return 0;
}

static int serve_tcp(bridge_context_t *ctx)
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) {
        perror("socket");
        return -1;
    }

    int reuse = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons((uint16_t)ctx->cfg.tcp_port);

    if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(server, 4) != 0) {
        perror("tcp listen");
        close(server);
        return -1;
    }

    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("accept");
            close(server);
            return -1;
        }

        FILE *in = fdopen(client, "r");
        FILE *out = fdopen(dup(client), "w");
        if (in != NULL && out != NULL) {
            serve_stream(ctx, in, out);
        }
        if (in != NULL) {
            fclose(in);
        }
        if (out != NULL) {
            fclose(out);
        }
    }
}

int main(int argc, char **argv)
{
    bridge_context_t ctx;
    memset(&ctx, 0, sizeof(ctx));

    if (parse_args(argc, argv, &ctx.cfg) != 0) {
        usage(argv[0]);
        return 2;
    }

    if (open_bus(&ctx) != 0) {
        return 1;
    }

    if (ctx.cfg.tcp_port > 0) {
        return serve_tcp(&ctx) == 0 ? 0 : 1;
    }

    return serve_stream(&ctx, stdin, stdout) == 0 ? 0 : 1;
}
