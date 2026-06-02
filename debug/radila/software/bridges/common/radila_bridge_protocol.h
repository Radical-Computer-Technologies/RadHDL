#ifndef RADILA_BRIDGE_PROTOCOL_H
#define RADILA_BRIDGE_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RADILA_BRIDGE_MAX_DATA 256u
#define RADILA_BRIDGE_MAX_LINE 768u

typedef enum {
    RADILA_BRIDGE_OP_NONE = 0,
    RADILA_BRIDGE_OP_READ,
    RADILA_BRIDGE_OP_WRITE,
    RADILA_BRIDGE_OP_PING
} radila_bridge_op_t;

typedef struct {
    radila_bridge_op_t op;
    uint32_t addr;
    size_t len;
    uint8_t data[RADILA_BRIDGE_MAX_DATA];
} radila_bridge_cmd_t;

uint16_t radila_bridge_crc16(const char *data, size_t len);
int radila_bridge_parse_line(const char *line, bool require_crc, radila_bridge_cmd_t *cmd);
int radila_bridge_format_read_ok(char *out, size_t out_len, const uint8_t *data, size_t len, bool append_crc);
int radila_bridge_format_write_ok(char *out, size_t out_len, bool append_crc);
int radila_bridge_format_pong(char *out, size_t out_len, bool append_crc);
int radila_bridge_format_error(char *out, size_t out_len, const char *reason, bool append_crc);

#ifdef __cplusplus
}
#endif

#endif
