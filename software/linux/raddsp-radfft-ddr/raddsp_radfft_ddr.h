/* SPDX-License-Identifier: MIT */
#ifndef _UAPI_RADDSP_RADFFT_DDR_H
#define _UAPI_RADDSP_RADFFT_DDR_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define RADDSP_RADFFT_DDR_IOC_MAGIC 'F'
#define RADDSP_RADFFT_DDR_API_VERSION 4

#define RADDSP_RADFFT_DDR_MODE_AXIS_TO_DDR 0u
#define RADDSP_RADFFT_DDR_MODE_DDR_TO_AXIS 1u
#define RADDSP_RADFFT_DDR_MODE_MEM_TO_MEM_FFT 2u
#define RADDSP_RADFFT_DDR_MODE_AXIS_TO_AXIS_FFT 3u

#define RADDSP_RADFFT_DDR_CAP_IRQ        (1u << 0)
#define RADDSP_RADFFT_DDR_CAP_DMA_COHERENT (1u << 1)
#define RADDSP_RADFFT_DDR_CAP_FFT_EXEC   (1u << 2)
#define RADDSP_RADFFT_DDR_CAP_FFT_BATCH  (1u << 3)

#define RADDSP_RADFFT_DDR_FLAG_FFT_SRC_AXIS (1u << 0)
#define RADDSP_RADFFT_DDR_FLAG_FFT_DST_AXIS (1u << 1)

#define RADDSP_RADFFT_DDR_STATUS_BUSY    (1u << 0)
#define RADDSP_RADFFT_DDR_STATUS_DONE    (1u << 1)
#define RADDSP_RADFFT_DDR_STATUS_ERROR   (1u << 2)
#define RADDSP_RADFFT_DDR_STATUS_UNSUPPORTED (1u << 3)

struct raddsp_radfft_ddr_info {
	__u32 api_version;
	__u32 capabilities;
	__u64 buffer_phys;
	__u64 buffer_size;
	__u32 axi_data_bytes;
	__u32 max_burst_beats;
	__u32 point_log2;
	__u32 max_point_log2;
	__u32 max_input_width;
	__u32 max_output_width;
	__u32 twiddle_width;
	__u32 supported_radix;
	__u32 max_multiplier_lanes;
	__u32 active_config;
	__u32 batch_done_count;
};

struct raddsp_radfft_ddr_config {
	__u64 base_addr;
	__u64 output_addr;
	__u64 twiddle_addr;
	__u32 length_bytes;
	__u32 region_bytes;
	__u32 point_log2;
	__u32 burst_beats;
	__u32 mode;
	__u32 flags;
	__u32 radix;
	__u32 input_width;
	__u32 output_width;
	__u32 multiplier_lanes;
	__u32 batch_count;
	__u32 source_stride_bytes;
	__u32 dest_stride_bytes;
	__u32 reserved0;
};

struct raddsp_radfft_ddr_status {
	__u32 control;
	__u32 status;
	__u64 current_write_addr;
	__u64 current_read_addr;
};

struct raddsp_radfft_ddr_wait {
	__u32 timeout_ms;
	__u32 status;
};

#define RADDSP_RADFFT_DDR_IOC_GET_INFO \
	_IOR(RADDSP_RADFFT_DDR_IOC_MAGIC, 0x00, struct raddsp_radfft_ddr_info)
#define RADDSP_RADFFT_DDR_IOC_CONFIGURE \
	_IOW(RADDSP_RADFFT_DDR_IOC_MAGIC, 0x01, struct raddsp_radfft_ddr_config)
#define RADDSP_RADFFT_DDR_IOC_START \
	_IOW(RADDSP_RADFFT_DDR_IOC_MAGIC, 0x02, __u32)
#define RADDSP_RADFFT_DDR_IOC_GET_STATUS \
	_IOR(RADDSP_RADFFT_DDR_IOC_MAGIC, 0x03, struct raddsp_radfft_ddr_status)
#define RADDSP_RADFFT_DDR_IOC_WAIT \
	_IOWR(RADDSP_RADFFT_DDR_IOC_MAGIC, 0x04, struct raddsp_radfft_ddr_wait)
#define RADDSP_RADFFT_DDR_IOC_RESET_STATUS \
	_IO(RADDSP_RADFFT_DDR_IOC_MAGIC, 0x05)

#endif
