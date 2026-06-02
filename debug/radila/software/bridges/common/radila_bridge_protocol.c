#include "radila_bridge_protocol.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int hex_value(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

uint16_t radila_bridge_crc16(const char *data, size_t len)
{
    uint16_t crc = 0xffffu;

    for (size_t i = 0; i < len; ++i) {
        crc ^= (uint16_t)(uint8_t)data[i] << 8;
        for (int bit = 0; bit < 8; ++bit) {
            if ((crc & 0x8000u) != 0u) {
                crc = (uint16_t)((crc << 1) ^ 0x1021u);
            } else {
                crc = (uint16_t)(crc << 1);
            }
        }
    }

    return crc;
}

static char *trim(char *text)
{
    while (isspace((unsigned char)*text)) {
        ++text;
    }

    char *end = text + strlen(text);
    while (end > text && isspace((unsigned char)end[-1])) {
        *--end = '\0';
    }

    return text;
}

static int parse_u32(const char *text, uint32_t *value)
{
    char *end = NULL;
    unsigned long parsed = strtoul(text, &end, 0);
    if (end == text || *end != '\0' || parsed > 0xfffffffful) {
        return -1;
    }
    *value = (uint32_t)parsed;
    return 0;
}

static int parse_size(const char *text, size_t *value)
{
    char *end = NULL;
    unsigned long parsed = strtoul(text, &end, 0);
    if (end == text || *end != '\0' || parsed > RADILA_BRIDGE_MAX_DATA) {
        return -1;
    }
    *value = (size_t)parsed;
    return 0;
}

static int parse_hex_bytes(const char *text, uint8_t *data, size_t *len)
{
    size_t out = 0;
    int high = -1;

    for (const char *p = text; *p != '\0'; ++p) {
        if (isspace((unsigned char)*p) || *p == '_' || *p == ':') {
            continue;
        }
        int nibble = hex_value(*p);
        if (nibble < 0) {
            return -1;
        }
        if (high < 0) {
            high = nibble;
        } else {
            if (out >= RADILA_BRIDGE_MAX_DATA) {
                return -1;
            }
            data[out++] = (uint8_t)((high << 4) | nibble);
            high = -1;
        }
    }

    if (high >= 0) {
        return -1;
    }

    *len = out;
    return 0;
}

static int verify_crc(char *line, bool require_crc)
{
    char *star = strrchr(line, '*');
    if (star == NULL) {
        return require_crc ? -1 : 0;
    }

    *star = '\0';
    char *crc_text = trim(star + 1);
    if (strlen(crc_text) != 4u) {
        return -1;
    }

    char *end = NULL;
    unsigned long expected = strtoul(crc_text, &end, 16);
    if (end == crc_text || *end != '\0' || expected > 0xfffful) {
        return -1;
    }

    const uint16_t actual = radila_bridge_crc16(line, strlen(line));
    return actual == (uint16_t)expected ? 0 : -1;
}

int radila_bridge_parse_line(const char *line, bool require_crc, radila_bridge_cmd_t *cmd)
{
    if (line == NULL || cmd == NULL) {
        return -1;
    }

    char copy[RADILA_BRIDGE_MAX_LINE];
    const size_t input_len = strnlen(line, sizeof(copy));
    if (input_len == sizeof(copy)) {
        return -1;
    }
    memcpy(copy, line, input_len + 1u);

    char *body = trim(copy);
    if (verify_crc(body, require_crc) != 0) {
        return -1;
    }
    body = trim(body);

    memset(cmd, 0, sizeof(*cmd));

    char *save = NULL;
    char *op = strtok_r(body, " \t\r\n", &save);
    if (op == NULL) {
        return -1;
    }

    if (strcmp(op, "PING") == 0) {
        cmd->op = RADILA_BRIDGE_OP_PING;
        return 0;
    }

    char *addr = strtok_r(NULL, " \t\r\n", &save);
    if (addr == NULL || parse_u32(addr, &cmd->addr) != 0) {
        return -1;
    }

    if (strcmp(op, "R") == 0 || strcmp(op, "READ") == 0) {
        char *len = strtok_r(NULL, " \t\r\n", &save);
        if (len == NULL || parse_size(len, &cmd->len) != 0) {
            return -1;
        }
        cmd->op = RADILA_BRIDGE_OP_READ;
        return 0;
    }

    if (strcmp(op, "W") == 0 || strcmp(op, "WRITE") == 0) {
        char *hex = strtok_r(NULL, "\r\n", &save);
        if (hex == NULL || parse_hex_bytes(hex, cmd->data, &cmd->len) != 0 || cmd->len == 0u) {
            return -1;
        }
        cmd->op = RADILA_BRIDGE_OP_WRITE;
        return 0;
    }

    return -1;
}

static int append_crc_and_newline(char *out, size_t out_len, bool append_crc)
{
    const size_t used = strlen(out);
    if (append_crc) {
        const uint16_t crc = radila_bridge_crc16(out, used);
        return snprintf(out + used, out_len - used, " *%04X\n", crc);
    }
    return snprintf(out + used, out_len - used, "\n");
}

int radila_bridge_format_read_ok(char *out, size_t out_len, const uint8_t *data, size_t len, bool append_crc)
{
    if (out == NULL || (data == NULL && len != 0u) || len > RADILA_BRIDGE_MAX_DATA) {
        return -1;
    }

    int written = snprintf(out, out_len, "OK");
    if (written < 0 || (size_t)written >= out_len) {
        return -1;
    }

    for (size_t i = 0; i < len; ++i) {
        const size_t used = strlen(out);
        written = snprintf(out + used, out_len - used, " %02X", data[i]);
        if (written < 0 || (size_t)written >= out_len - used) {
            return -1;
        }
    }

    return append_crc_and_newline(out, out_len, append_crc);
}

int radila_bridge_format_write_ok(char *out, size_t out_len, bool append_crc)
{
    if (out == NULL || snprintf(out, out_len, "OK") < 0) {
        return -1;
    }
    return append_crc_and_newline(out, out_len, append_crc);
}

int radila_bridge_format_pong(char *out, size_t out_len, bool append_crc)
{
    if (out == NULL || snprintf(out, out_len, "OK PONG") < 0) {
        return -1;
    }
    return append_crc_and_newline(out, out_len, append_crc);
}

int radila_bridge_format_error(char *out, size_t out_len, const char *reason, bool append_crc)
{
    if (out == NULL) {
        return -1;
    }
    if (reason == NULL || *reason == '\0') {
        reason = "bad-command";
    }
    if (snprintf(out, out_len, "ERR %s", reason) < 0) {
        return -1;
    }
    return append_crc_and_newline(out, out_len, append_crc);
}
