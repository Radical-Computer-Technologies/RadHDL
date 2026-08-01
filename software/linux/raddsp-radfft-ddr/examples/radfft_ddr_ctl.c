// SPDX-License-Identifier: MIT
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "raddsp_radfft_ddr.h"

static int parse_u32(const char *text, uint32_t *out)
{
	char *end = NULL;
	unsigned long value;

	errno = 0;
	value = strtoul(text, &end, 0);
	if (errno || end == text || *end || value > UINT32_MAX)
		return -1;
	*out = (uint32_t)value;
	return 0;
}

static void usage(const char *prog)
{
	fprintf(stderr,
		"usage: %s <device> <mode> <length-bytes> [pattern]\n"
		"  mode: 0 axis-to-ddr, 1 ddr-to-axis, 2 ddr-fft-ddr\n",
		prog);
}

int main(int argc, char **argv)
{
	struct raddsp_radfft_ddr_info info;
	struct raddsp_radfft_ddr_config cfg;
	struct raddsp_radfft_ddr_wait wait_arg;
	struct raddsp_radfft_ddr_status status;
	uint32_t mode;
	uint32_t length;
	uint32_t pattern = 0x1000;
	uint64_t twiddle_offset = 0;
	volatile uint32_t *words;
	void *map;
	int fd;
	int ret;

	if (argc < 4 || argc > 5) {
		usage(argv[0]);
		return 2;
	}
	if (parse_u32(argv[2], &mode) || parse_u32(argv[3], &length)) {
		usage(argv[0]);
		return 2;
	}
	if (argc == 5 && parse_u32(argv[4], &pattern)) {
		usage(argv[0]);
		return 2;
	}

	fd = open(argv[1], O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror("open");
		return 1;
	}

	ret = ioctl(fd, RADDSP_RADFFT_DDR_IOC_GET_INFO, &info);
	if (ret) {
		perror("GET_INFO");
		close(fd);
		return 1;
	}

	if (length == 0 || length > info.buffer_size) {
		fprintf(stderr, "invalid length %u for buffer size %" PRIu64 "\n",
			length, (uint64_t)info.buffer_size);
		close(fd);
		return 1;
	}
	if (mode == RADDSP_RADFFT_DDR_MODE_MEM_TO_MEM_FFT) {
		twiddle_offset = length;
		if ((uint64_t)length * 2 > info.buffer_size) {
			fprintf(stderr,
				"FFT mode needs room for samples/output and twiddles: length=%u buffer=%" PRIu64 "\n",
				length, (uint64_t)info.buffer_size);
			close(fd);
			return 1;
		}
	}

	map = mmap(NULL, info.buffer_size, PROT_READ | PROT_WRITE, MAP_SHARED,
		   fd, 0);
	if (map == MAP_FAILED) {
		perror("mmap");
		close(fd);
		return 1;
	}

	if (mode == RADDSP_RADFFT_DDR_MODE_DDR_TO_AXIS ||
	    mode == RADDSP_RADFFT_DDR_MODE_MEM_TO_MEM_FFT ||
	    mode == RADDSP_RADFFT_DDR_MODE_AXIS_TO_AXIS_FFT) {
		size_t word_count = length / sizeof(uint32_t);

		words = map;
		for (size_t i = 0; i < word_count; i++)
			words[i] = pattern + i;
	}
	if (mode == RADDSP_RADFFT_DDR_MODE_MEM_TO_MEM_FFT) {
		size_t word_count = length / sizeof(uint32_t);
		volatile uint32_t *twiddles =
			(volatile uint32_t *)((volatile uint8_t *)map + twiddle_offset);

		for (size_t i = 0; i < word_count; i++)
			twiddles[i] = 0x7fff0000u;
	}

	memset(&cfg, 0, sizeof(cfg));
	cfg.base_addr = info.buffer_phys;
	cfg.output_addr = info.buffer_phys;
	cfg.twiddle_addr = mode == RADDSP_RADFFT_DDR_MODE_MEM_TO_MEM_FFT ?
		info.buffer_phys + twiddle_offset : 0;
	cfg.length_bytes = length;
	cfg.region_bytes = (uint32_t)info.buffer_size;
	cfg.point_log2 = info.point_log2;
	cfg.burst_beats = info.max_burst_beats;
	cfg.mode = mode;
	cfg.radix = 2;
	cfg.input_width = info.max_input_width;
	cfg.output_width = info.max_output_width;
	cfg.multiplier_lanes = info.max_multiplier_lanes;

	ret = ioctl(fd, RADDSP_RADFFT_DDR_IOC_CONFIGURE, &cfg);
	if (ret) {
		perror("CONFIGURE");
		munmap(map, info.buffer_size);
		close(fd);
		return 1;
	}

	ret = ioctl(fd, RADDSP_RADFFT_DDR_IOC_START, &mode);
	if (ret) {
		perror("START");
		munmap(map, info.buffer_size);
		close(fd);
		return 1;
	}

	memset(&wait_arg, 0, sizeof(wait_arg));
	wait_arg.timeout_ms = 5000;
	ret = ioctl(fd, RADDSP_RADFFT_DDR_IOC_WAIT, &wait_arg);
	if (ret) {
		perror("WAIT");
		munmap(map, info.buffer_size);
		close(fd);
		return 1;
	}

	ret = ioctl(fd, RADDSP_RADFFT_DDR_IOC_GET_STATUS, &status);
	if (ret) {
		perror("GET_STATUS");
		munmap(map, info.buffer_size);
		close(fd);
		return 1;
	}

	printf("status=0x%08x wait_status=0x%08x wr=0x%016" PRIx64
	       " rd=0x%016" PRIx64 "\n",
	       status.status, wait_arg.status,
	       (uint64_t)status.current_write_addr,
	       (uint64_t)status.current_read_addr);

	munmap(map, info.buffer_size);
	close(fd);
	return (status.status & RADDSP_RADFFT_DDR_STATUS_ERROR) ? 1 : 0;
}
