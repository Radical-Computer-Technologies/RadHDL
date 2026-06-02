#include "radila_bridge_protocol.h"

#include "hardware/gpio.h"
#include "hardware/i2c.h"
#include "hardware/spi.h"
#include "hardware/uart.h"
#include "pico/stdlib.h"

#if RADILA_PICO_ENABLE_TCP
#include "pico/cyw43_arch.h"
#include "lwip/tcp.h"
#endif

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define RADILA_UART uart0
#define RADILA_UART_BAUD 115200u
#define RADILA_UART_TX_PIN 0u
#define RADILA_UART_RX_PIN 1u

#define RADILA_SPI spi0
#define RADILA_SPI_SCK_PIN 2u
#define RADILA_SPI_MOSI_PIN 3u
#define RADILA_SPI_MISO_PIN 4u
#define RADILA_SPI_CSN_PIN 5u
#define RADILA_SPI_BAUD 10000000u

#define RADILA_I2C i2c0
#define RADILA_I2C_SDA_PIN 4u
#define RADILA_I2C_SCL_PIN 5u
#define RADILA_I2C_BAUD 400000u
#define RADILA_I2C_ADDR 0x42u

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

static void init_uart(void)
{
    uart_init(RADILA_UART, RADILA_UART_BAUD);
    gpio_set_function(RADILA_UART_TX_PIN, GPIO_FUNC_UART);
    gpio_set_function(RADILA_UART_RX_PIN, GPIO_FUNC_UART);
}

static void init_spi(void)
{
    spi_init(RADILA_SPI, RADILA_SPI_BAUD);
    gpio_set_function(RADILA_SPI_SCK_PIN, GPIO_FUNC_SPI);
    gpio_set_function(RADILA_SPI_MOSI_PIN, GPIO_FUNC_SPI);
    gpio_set_function(RADILA_SPI_MISO_PIN, GPIO_FUNC_SPI);
    gpio_init(RADILA_SPI_CSN_PIN);
    gpio_set_dir(RADILA_SPI_CSN_PIN, GPIO_OUT);
    gpio_put(RADILA_SPI_CSN_PIN, 1);
}

static void init_i2c(void)
{
    i2c_init(RADILA_I2C, RADILA_I2C_BAUD);
    gpio_set_function(RADILA_I2C_SDA_PIN, GPIO_FUNC_I2C);
    gpio_set_function(RADILA_I2C_SCL_PIN, GPIO_FUNC_I2C);
    gpio_pull_up(RADILA_I2C_SDA_PIN);
    gpio_pull_up(RADILA_I2C_SCL_PIN);
}

static int spi_exchange(uint8_t *tx, uint8_t *rx, size_t len)
{
    gpio_put(RADILA_SPI_CSN_PIN, 0);
    const int rc = spi_write_read_blocking(RADILA_SPI, tx, rx, len);
    gpio_put(RADILA_SPI_CSN_PIN, 1);
    return rc == (int)len ? 0 : -1;
}

static int bus_read(uint32_t addr, uint8_t *data, size_t len)
{
    uint8_t header[7];
    make_header(header, 0x01u, addr, len);

#if defined(RADILA_PICO_BUS_i2c)
    if (i2c_write_blocking(RADILA_I2C, RADILA_I2C_ADDR, header, sizeof(header), true) != (int)sizeof(header)) {
        return -1;
    }
    return i2c_read_blocking(RADILA_I2C, RADILA_I2C_ADDR, data, len, false) == (int)len ? 0 : -1;
#else
    uint8_t tx[7 + RADILA_BRIDGE_MAX_DATA];
    uint8_t rx[7 + RADILA_BRIDGE_MAX_DATA];
    memset(tx, 0, sizeof(tx));
    memset(rx, 0, sizeof(rx));
    memcpy(tx, header, sizeof(header));
    if (spi_exchange(tx, rx, sizeof(header) + len) != 0) {
        return -1;
    }
    memcpy(data, rx + sizeof(header), len);
    return 0;
#endif
}

static int bus_write(uint32_t addr, const uint8_t *data, size_t len)
{
    uint8_t packet[7 + RADILA_BRIDGE_MAX_DATA];
    make_header(packet, 0x02u, addr, len);
    memcpy(packet + 7, data, len);

#if defined(RADILA_PICO_BUS_i2c)
    return i2c_write_blocking(RADILA_I2C, RADILA_I2C_ADDR, packet, 7 + len, false) == (int)(7 + len) ? 0 : -1;
#else
    uint8_t rx[sizeof(packet)];
    memset(rx, 0, sizeof(rx));
    return spi_exchange(packet, rx, 7 + len);
#endif
}

static int process_line(const char *line, bool require_crc, char *reply, size_t reply_len)
{
    radila_bridge_cmd_t cmd;
    if (radila_bridge_parse_line(line, require_crc, &cmd) != 0) {
        return radila_bridge_format_error(reply, reply_len, "parse", require_crc);
    }

    if (cmd.op == RADILA_BRIDGE_OP_PING) {
        return radila_bridge_format_pong(reply, reply_len, require_crc);
    }

    if (cmd.op == RADILA_BRIDGE_OP_READ) {
        uint8_t data[RADILA_BRIDGE_MAX_DATA];
        if (bus_read(cmd.addr, data, cmd.len) != 0) {
            return radila_bridge_format_error(reply, reply_len, "read", require_crc);
        }
        return radila_bridge_format_read_ok(reply, reply_len, data, cmd.len, require_crc);
    }

    if (cmd.op == RADILA_BRIDGE_OP_WRITE) {
        if (bus_write(cmd.addr, cmd.data, cmd.len) != 0) {
            return radila_bridge_format_error(reply, reply_len, "write", require_crc);
        }
        return radila_bridge_format_write_ok(reply, reply_len, require_crc);
    }

    return radila_bridge_format_error(reply, reply_len, "op", require_crc);
}

static void uart_write_string(const char *text)
{
    while (*text != '\0') {
        uart_putc_raw(RADILA_UART, *text++);
    }
}

static void poll_uart(void)
{
    static char line[RADILA_BRIDGE_MAX_LINE];
    static size_t used = 0;

    while (uart_is_readable(RADILA_UART)) {
        char c = (char)uart_getc(RADILA_UART);
        if (c == '\r') {
            continue;
        }
        if (c == '\n') {
            line[used] = '\0';
            char reply[RADILA_BRIDGE_MAX_LINE];
            if (process_line(line, true, reply, sizeof(reply)) < 0) {
                radila_bridge_format_error(reply, sizeof(reply), "internal", true);
            }
            uart_write_string(reply);
            used = 0;
        } else if (used + 1u < sizeof(line)) {
            line[used++] = c;
        } else {
            used = 0;
            uart_write_string("ERR overflow *6F5F\n");
        }
    }
}

#if RADILA_PICO_ENABLE_TCP
static err_t tcp_recv_cb(void *arg, struct tcp_pcb *pcb, struct pbuf *p, err_t err)
{
    (void)arg;
    if (p == NULL) {
        tcp_close(pcb);
        return ERR_OK;
    }
    if (err != ERR_OK) {
        pbuf_free(p);
        return err;
    }

    char line[RADILA_BRIDGE_MAX_LINE];
    const uint16_t copy_len = p->tot_len < sizeof(line) - 1u ? p->tot_len : sizeof(line) - 1u;
    pbuf_copy_partial(p, line, copy_len, 0);
    line[copy_len] = '\0';

    char reply[RADILA_BRIDGE_MAX_LINE];
    if (process_line(line, false, reply, sizeof(reply)) < 0) {
        radila_bridge_format_error(reply, sizeof(reply), "internal", false);
    }
    tcp_write(pcb, reply, strlen(reply), TCP_WRITE_FLAG_COPY);
    tcp_recved(pcb, p->tot_len);
    pbuf_free(p);
    return ERR_OK;
}

static err_t tcp_accept_cb(void *arg, struct tcp_pcb *client, err_t err)
{
    (void)arg;
    if (err != ERR_OK) {
        return err;
    }
    tcp_recv(client, tcp_recv_cb);
    return ERR_OK;
}

static void init_tcp(void)
{
    if (cyw43_arch_init() != 0) {
        return;
    }
    cyw43_arch_enable_sta_mode();
    struct tcp_pcb *server = tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (server == NULL) {
        return;
    }
    if (tcp_bind(server, IP_ANY_TYPE, 9738) != ERR_OK) {
        tcp_close(server);
        return;
    }
    server = tcp_listen(server);
    tcp_accept(server, tcp_accept_cb);
}
#else
static void init_tcp(void)
{
}
#endif

int main(void)
{
    stdio_init_all();
    init_uart();

#if defined(RADILA_PICO_BUS_i2c)
    init_i2c();
#else
    init_spi();
#endif

    init_tcp();

    for (;;) {
        poll_uart();
        sleep_ms(1);
    }
}
