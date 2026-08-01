// SPDX-License-Identifier: GPL-2.0 OR MIT
/*
 * RADHDL RADDsp DDR-backed RADFFT platform driver.
 *
 * This driver targets AXI-Lite controlled RADFFT DDR cores on Zynq-7000 and
 * Zynq UltraScale+ platforms. The sample buffer is supplied by a device-tree
 * reserved-memory region and exported through mmap().
 */

#include <linux/bitops.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/miscdevice.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/of_device.h>
#include <linux/of_dma.h>
#include <linux/of_reserved_mem.h>
#include <linux/overflow.h>
#include <linux/platform_device.h>
#include <linux/poll.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/version.h>

#include "raddsp_radfft_ddr.h"

#define RADFFT_REG_CONTROL      0x00
#define RADFFT_REG_STATUS       0x04
#define RADFFT_REG_BASE_LO      0x08
#define RADFFT_REG_BASE_HI      0x0c
#define RADFFT_REG_OUT_LO       0x10
#define RADFFT_REG_OUT_HI       0x14
#define RADFFT_REG_LENGTH       0x18
#define RADFFT_REG_REGION       0x1c
#define RADFFT_REG_POINT_LOG2   0x20
#define RADFFT_REG_BURST_BEATS  0x24
#define RADFFT_REG_WR_ADDR_LO   0x28
#define RADFFT_REG_RD_ADDR_LO   0x2c
#define RADFFT_REG_TWIDDLE_LO   0x30
#define RADFFT_REG_TWIDDLE_HI   0x34
#define RADFFT_REG_FFT_CONFIG   0x38
#define RADFFT_REG_MAGIC        0x3c
#define RADFFT_REG_CAP0         0x40
#define RADFFT_REG_CAP1         0x44
#define RADFFT_REG_BATCH_COUNT  0x48
#define RADFFT_REG_SRC_STRIDE   0x4c
#define RADFFT_REG_DST_STRIDE   0x50
#define RADFFT_REG_BATCH_DONE   0x54

#define RADFFT_MAGIC            0x52464444u
#define RADFFT_CONTROL_START    BIT(0)
#define RADFFT_CONTROL_CLEAR    BIT(31)
#define RADFFT_CONTROL_IRQ_EN   BIT(8)
#define RADFFT_CONTROL_MODE_SHIFT 4
#define RADFFT_CONTROL_MODE_MASK GENMASK(5, 4)

#define RADFFT_STATUS_DONE_OR_ERROR \
	(RADDSP_RADFFT_DDR_STATUS_DONE | RADDSP_RADFFT_DDR_STATUS_ERROR)

struct raddsp_radfft_ddr_dev {
	struct device *dev;
	void __iomem *regs;
	struct miscdevice miscdev;
	struct mutex lock;
	struct completion done;
	wait_queue_head_t waitq;
	phys_addr_t buf_phys;
	resource_size_t buf_size;
	int irq;
	bool dma_coherent;
	u32 axi_data_bytes;
	u32 max_burst_beats;
	u32 point_log2;
	u32 max_point_log2;
	u32 max_input_width;
	u32 max_output_width;
	u32 twiddle_width;
	u32 supported_radix;
	u32 max_multiplier_lanes;
};

static inline u32 radfft_readl(struct raddsp_radfft_ddr_dev *rf, u32 reg)
{
	return readl(rf->regs + reg);
}

static inline void radfft_writel(struct raddsp_radfft_ddr_dev *rf, u32 reg,
				 u32 value)
{
	writel(value, rf->regs + reg);
}

static void radfft_write_addr(struct raddsp_radfft_ddr_dev *rf, u32 lo_reg,
			      u32 hi_reg, u64 addr)
{
	radfft_writel(rf, lo_reg, lower_32_bits(addr));
	radfft_writel(rf, hi_reg, upper_32_bits(addr));
}

static u64 radfft_read_addr32(struct raddsp_radfft_ddr_dev *rf, u32 lo_reg)
{
	return radfft_readl(rf, lo_reg);
}

static u32 radfft_status(struct raddsp_radfft_ddr_dev *rf)
{
	return radfft_readl(rf, RADFFT_REG_STATUS);
}

static void radfft_clear_status(struct raddsp_radfft_ddr_dev *rf)
{
	radfft_writel(rf, RADFFT_REG_CONTROL, RADFFT_CONTROL_CLEAR);
}

static int radfft_validate_buffer_range(struct raddsp_radfft_ddr_dev *rf,
					u64 addr, u32 length)
{
	u64 end;

	if (!length)
		return -EINVAL;

	if (check_add_overflow(addr, (u64)length, &end))
		return -EINVAL;

	if (addr < rf->buf_phys || end > rf->buf_phys + rf->buf_size)
		return -ERANGE;

	return 0;
}

static int radfft_validate_batch_range(struct raddsp_radfft_ddr_dev *rf,
				       u64 addr, u32 frame_length,
				       u32 batch_count, u32 stride)
{
	u64 last_offset;
	u64 total_length;

	if (!batch_count)
		batch_count = 1;
	if (!stride)
		stride = frame_length;

	if (check_mul_overflow((u64)(batch_count - 1), (u64)stride,
			       &last_offset))
		return -EINVAL;
	if (check_add_overflow(last_offset, (u64)frame_length, &total_length))
		return -EINVAL;

	return radfft_validate_buffer_range(rf, addr, total_length);
}

static int radfft_width_code(u32 width)
{
	switch (width) {
	case 16:
		return 0;
	case 24:
		return 1;
	case 32:
		return 2;
	default:
		return -EINVAL;
	}
}

static int radfft_lane_code(u32 lanes)
{
	switch (lanes) {
	case 16:
		return 0;
	case 32:
		return 1;
	case 64:
		return 2;
	case 128:
		return 3;
	default:
		return -EINVAL;
	}
}

static int radfft_configure(struct raddsp_radfft_ddr_dev *rf,
			    const struct raddsp_radfft_ddr_config *cfg)
{
	u32 region = cfg->region_bytes;
	u32 burst = cfg->burst_beats;
	u32 point_log2 = cfg->point_log2 ? cfg->point_log2 : rf->max_point_log2;
	u32 radix = cfg->radix ? cfg->radix : 2;
	u32 input_width = cfg->input_width ? cfg->input_width : rf->max_input_width;
	u32 output_width = cfg->output_width ? cfg->output_width : rf->max_output_width;
	u32 lanes = cfg->multiplier_lanes ? cfg->multiplier_lanes : rf->max_multiplier_lanes;
	u32 batch_count = cfg->batch_count ? cfg->batch_count : 1;
	u32 src_stride = cfg->source_stride_bytes ? cfg->source_stride_bytes : cfg->length_bytes;
	u32 dst_stride = cfg->dest_stride_bytes ? cfg->dest_stride_bytes : cfg->length_bytes;
	u32 flags = cfg->flags;
	u32 fft_config = 0;
	int input_code;
	int output_code;
	int lane_code;
	int ret;

	if (cfg->mode == RADDSP_RADFFT_DDR_MODE_AXIS_TO_AXIS_FFT)
		flags |= RADDSP_RADFFT_DDR_FLAG_FFT_SRC_AXIS |
			 RADDSP_RADFFT_DDR_FLAG_FFT_DST_AXIS;

	if (!(flags & RADDSP_RADFFT_DDR_FLAG_FFT_SRC_AXIS)) {
		ret = radfft_validate_batch_range(rf, cfg->base_addr,
						  cfg->length_bytes,
						  batch_count, src_stride);
		if (ret)
			return ret;
	}

	if (!(flags & RADDSP_RADFFT_DDR_FLAG_FFT_DST_AXIS)) {
		u64 dst_addr = cfg->output_addr ? cfg->output_addr : cfg->base_addr;

		ret = radfft_validate_batch_range(rf, dst_addr,
						  cfg->length_bytes,
						  batch_count, dst_stride);
		if (ret)
			return ret;
	}

	if (cfg->mode == RADDSP_RADFFT_DDR_MODE_MEM_TO_MEM_FFT) {
		if (!cfg->twiddle_addr)
			return -EINVAL;
		ret = radfft_validate_buffer_range(rf, cfg->twiddle_addr,
						   cfg->length_bytes);
		if (ret)
			return ret;
	} else if (cfg->twiddle_addr) {
		ret = radfft_validate_buffer_range(rf, cfg->twiddle_addr,
						   cfg->length_bytes);
		if (ret)
			return ret;
	}

	if (region == 0 || region > rf->buf_size)
		region = min_t(resource_size_t, rf->buf_size, U32_MAX);

	if (burst == 0)
		burst = rf->max_burst_beats ? rf->max_burst_beats : 1;
	if (rf->max_burst_beats && burst > rf->max_burst_beats)
		burst = rf->max_burst_beats;

	if (point_log2 > rf->max_point_log2)
		return -EINVAL;
	if (radix != 2 && radix != 4)
		return -EINVAL;
	if (radix == 2 && !(rf->supported_radix & BIT(0)))
		return -EINVAL;
	if (radix == 4 && !(rf->supported_radix & BIT(1)))
		return -EINVAL;
	if (input_width > rf->max_input_width || output_width > rf->max_output_width)
		return -EINVAL;
	if (lanes > rf->max_multiplier_lanes)
		return -EINVAL;
	if (batch_count == 0)
		return -EINVAL;
	if (src_stride < cfg->length_bytes || dst_stride < cfg->length_bytes)
		return -EINVAL;

	input_code = radfft_width_code(input_width);
	output_code = radfft_width_code(output_width);
	lane_code = radfft_lane_code(lanes);
	if (input_code < 0 || output_code < 0 || lane_code < 0)
		return -EINVAL;

	if (radix == 4)
		fft_config |= BIT(0);
	if (flags & RADDSP_RADFFT_DDR_FLAG_FFT_SRC_AXIS)
		fft_config |= BIT(4);
	if (flags & RADDSP_RADFFT_DDR_FLAG_FFT_DST_AXIS)
		fft_config |= BIT(5);
	fft_config |= (input_code & 0x7) << 8;
	fft_config |= (output_code & 0x7) << 12;
	fft_config |= (lane_code & 0x3) << 16;

	radfft_write_addr(rf, RADFFT_REG_BASE_LO, RADFFT_REG_BASE_HI,
			  cfg->base_addr);
	radfft_write_addr(rf, RADFFT_REG_OUT_LO, RADFFT_REG_OUT_HI,
			  cfg->output_addr);
	radfft_write_addr(rf, RADFFT_REG_TWIDDLE_LO, RADFFT_REG_TWIDDLE_HI,
			  cfg->twiddle_addr);
	radfft_writel(rf, RADFFT_REG_LENGTH, cfg->length_bytes);
	radfft_writel(rf, RADFFT_REG_REGION, region);
	radfft_writel(rf, RADFFT_REG_POINT_LOG2, point_log2 & 0xff);
	radfft_writel(rf, RADFFT_REG_BURST_BEATS, burst & 0xff);
	radfft_writel(rf, RADFFT_REG_FFT_CONFIG, fft_config);
	radfft_writel(rf, RADFFT_REG_BATCH_COUNT, batch_count);
	radfft_writel(rf, RADFFT_REG_SRC_STRIDE, src_stride);
	radfft_writel(rf, RADFFT_REG_DST_STRIDE, dst_stride);

	rf->point_log2 = point_log2 & 0xff;
	return 0;
}

static int radfft_start_locked(struct raddsp_radfft_ddr_dev *rf, u32 mode)
{
	u32 control;
	u32 hw_mode = mode;

	if (mode > RADDSP_RADFFT_DDR_MODE_AXIS_TO_AXIS_FFT)
		return -EINVAL;
	if (mode == RADDSP_RADFFT_DDR_MODE_AXIS_TO_AXIS_FFT)
		hw_mode = RADDSP_RADFFT_DDR_MODE_MEM_TO_MEM_FFT;

	if (radfft_status(rf) & RADDSP_RADFFT_DDR_STATUS_BUSY)
		return -EBUSY;

	reinit_completion(&rf->done);
	radfft_clear_status(rf);

	/*
	 * Userspace may have populated the shared buffer through a write-combined
	 * mapping. Order those stores before the PL core starts issuing AXI reads.
	 */
	wmb();

	control = RADFFT_CONTROL_START | RADFFT_CONTROL_IRQ_EN;
	control |= (hw_mode << RADFFT_CONTROL_MODE_SHIFT) & RADFFT_CONTROL_MODE_MASK;
	radfft_writel(rf, RADFFT_REG_CONTROL, control);

	return 0;
}

static int radfft_copy_status(struct raddsp_radfft_ddr_dev *rf,
			      struct raddsp_radfft_ddr_status __user *argp)
{
	struct raddsp_radfft_ddr_status st;

	st.control = radfft_readl(rf, RADFFT_REG_CONTROL);
	st.status = radfft_status(rf);
	st.current_write_addr = radfft_read_addr32(rf, RADFFT_REG_WR_ADDR_LO);
	st.current_read_addr = radfft_read_addr32(rf, RADFFT_REG_RD_ADDR_LO);

	if (copy_to_user(argp, &st, sizeof(st)))
		return -EFAULT;

	return 0;
}

static long radfft_ioctl(struct file *file, unsigned int cmd,
			 unsigned long arg)
{
	struct raddsp_radfft_ddr_dev *rf = file->private_data;
	void __user *argp = (void __user *)arg;
	struct raddsp_radfft_ddr_config cfg;
	struct raddsp_radfft_ddr_info info;
	struct raddsp_radfft_ddr_wait wait;
	unsigned long timeout;
	u32 mode;
	u32 status;
	int ret = 0;

	if (_IOC_TYPE(cmd) != RADDSP_RADFFT_DDR_IOC_MAGIC)
		return -ENOTTY;

	mutex_lock(&rf->lock);
	switch (cmd) {
	case RADDSP_RADFFT_DDR_IOC_GET_INFO:
		memset(&info, 0, sizeof(info));
		info.api_version = RADDSP_RADFFT_DDR_API_VERSION;
		info.capabilities = 0;
		if (rf->irq >= 0)
			info.capabilities |= RADDSP_RADFFT_DDR_CAP_IRQ;
		if (rf->dma_coherent)
			info.capabilities |= RADDSP_RADFFT_DDR_CAP_DMA_COHERENT;
		info.capabilities |= RADDSP_RADFFT_DDR_CAP_FFT_EXEC;
		info.buffer_phys = rf->buf_phys;
		info.buffer_size = rf->buf_size;
		info.axi_data_bytes = rf->axi_data_bytes;
		info.max_burst_beats = rf->max_burst_beats;
		info.point_log2 = rf->point_log2;
		info.max_point_log2 = rf->max_point_log2;
		info.max_input_width = rf->max_input_width;
		info.max_output_width = rf->max_output_width;
		info.twiddle_width = rf->twiddle_width;
		info.supported_radix = rf->supported_radix;
		info.max_multiplier_lanes = rf->max_multiplier_lanes;
		info.active_config = radfft_readl(rf, RADFFT_REG_FFT_CONFIG);
		if (rf->supported_radix & BIT(2))
			info.capabilities |= RADDSP_RADFFT_DDR_CAP_FFT_BATCH;
		info.batch_done_count = radfft_readl(rf, RADFFT_REG_BATCH_DONE);
		if (copy_to_user(argp, &info, sizeof(info)))
			ret = -EFAULT;
		break;

	case RADDSP_RADFFT_DDR_IOC_CONFIGURE:
		if (copy_from_user(&cfg, argp, sizeof(cfg))) {
			ret = -EFAULT;
			break;
		}
		ret = radfft_configure(rf, &cfg);
		break;

	case RADDSP_RADFFT_DDR_IOC_START:
		if (copy_from_user(&mode, argp, sizeof(mode))) {
			ret = -EFAULT;
			break;
		}
		ret = radfft_start_locked(rf, mode);
		break;

	case RADDSP_RADFFT_DDR_IOC_GET_STATUS:
		ret = radfft_copy_status(rf, argp);
		break;

	case RADDSP_RADFFT_DDR_IOC_WAIT:
		if (copy_from_user(&wait, argp, sizeof(wait))) {
			ret = -EFAULT;
			break;
		}
		mutex_unlock(&rf->lock);
		if (rf->irq >= 0) {
			timeout = msecs_to_jiffies(wait.timeout_ms);
			if (!wait_for_completion_timeout(&rf->done, timeout)) {
				ret = -ETIMEDOUT;
			}
		} else {
			unsigned long deadline;

			deadline = jiffies + msecs_to_jiffies(wait.timeout_ms);
			do {
				status = radfft_status(rf);
				if (status & RADFFT_STATUS_DONE_OR_ERROR)
					break;
				usleep_range(100, 250);
			} while (time_before(jiffies, deadline));
			if (!(radfft_status(rf) & RADFFT_STATUS_DONE_OR_ERROR))
				ret = -ETIMEDOUT;
		}
		mutex_lock(&rf->lock);
		wait.status = radfft_status(rf);
		if (copy_to_user(argp, &wait, sizeof(wait)))
			ret = -EFAULT;
		break;

	case RADDSP_RADFFT_DDR_IOC_RESET_STATUS:
		radfft_clear_status(rf);
		break;

	default:
		ret = -ENOTTY;
		break;
	}
	mutex_unlock(&rf->lock);

	return ret;
}

static __poll_t radfft_poll(struct file *file, poll_table *wait)
{
	struct raddsp_radfft_ddr_dev *rf = file->private_data;
	__poll_t mask = 0;

	poll_wait(file, &rf->waitq, wait);
	if (radfft_status(rf) & RADFFT_STATUS_DONE_OR_ERROR)
		mask |= EPOLLIN | EPOLLRDNORM;

	return mask;
}

static int radfft_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct raddsp_radfft_ddr_dev *rf = file->private_data;
	unsigned long size = vma->vm_end - vma->vm_start;
	phys_addr_t offset = (phys_addr_t)vma->vm_pgoff << PAGE_SHIFT;
	phys_addr_t phys = rf->buf_phys + offset;

	if (offset >= rf->buf_size || size > rf->buf_size - offset)
		return -EINVAL;

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 3, 0)
	vm_flags_set(vma, VM_IO | VM_DONTEXPAND | VM_DONTDUMP);
#else
	vma->vm_flags |= VM_IO | VM_DONTEXPAND | VM_DONTDUMP;
#endif
	/*
	 * This is the userspace data-plane mapping. For non-coherent PL ports,
	 * keep it out of the normal cached mapping domain so a completion IRQ is
	 * enough to tell userspace that device writes are visible. The driver
	 * does not ioremap_wc() the buffer because it does not inspect payloads.
	 */
	if (!rf->dma_coherent)
		vma->vm_page_prot = pgprot_writecombine(vma->vm_page_prot);

	return remap_pfn_range(vma, vma->vm_start, phys >> PAGE_SHIFT, size,
			       vma->vm_page_prot);
}

static int radfft_open(struct inode *inode, struct file *file)
{
	struct miscdevice *misc = file->private_data;
	struct raddsp_radfft_ddr_dev *rf;

	rf = container_of(misc, struct raddsp_radfft_ddr_dev, miscdev);
	file->private_data = rf;
	return 0;
}

static const struct file_operations radfft_fops = {
	.owner = THIS_MODULE,
	.open = radfft_open,
	.unlocked_ioctl = radfft_ioctl,
	.compat_ioctl = radfft_ioctl,
	.mmap = radfft_mmap,
	.poll = radfft_poll,
	.llseek = no_llseek,
};

static irqreturn_t radfft_irq(int irq, void *data)
{
	struct raddsp_radfft_ddr_dev *rf = data;
	u32 status = radfft_status(rf);

	if (!(status & RADFFT_STATUS_DONE_OR_ERROR))
		return IRQ_NONE;

	complete_all(&rf->done);
	wake_up_interruptible(&rf->waitq);
	return IRQ_HANDLED;
}

static int radfft_reserved_mem(struct platform_device *pdev,
			       struct raddsp_radfft_ddr_dev *rf)
{
	struct device_node *mem_np;
	struct reserved_mem *rmem;

	mem_np = of_parse_phandle(pdev->dev.of_node, "memory-region", 0);
	if (!mem_np)
		return dev_err_probe(&pdev->dev, -EINVAL,
				     "missing memory-region phandle\n");

	rmem = of_reserved_mem_lookup(mem_np);
	of_node_put(mem_np);
	if (!rmem)
		return dev_err_probe(&pdev->dev, -EINVAL,
				     "memory-region is not reserved-memory\n");

	rf->buf_phys = rmem->base;
	rf->buf_size = rmem->size;
	if (!rf->buf_size)
		return dev_err_probe(&pdev->dev, -EINVAL,
				     "reserved-memory size is zero\n");

	return 0;
}

static int radfft_probe(struct platform_device *pdev)
{
	struct raddsp_radfft_ddr_dev *rf;
	struct resource *res;
	u32 cfg;
	int ret;

	rf = devm_kzalloc(&pdev->dev, sizeof(*rf), GFP_KERNEL);
	if (!rf)
		return -ENOMEM;

	rf->dev = &pdev->dev;
	mutex_init(&rf->lock);
	init_completion(&rf->done);
	init_waitqueue_head(&rf->waitq);

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	rf->regs = devm_ioremap_resource(&pdev->dev, res);
	if (IS_ERR(rf->regs))
		return PTR_ERR(rf->regs);

	ret = radfft_reserved_mem(pdev, rf);
	if (ret)
		return ret;

	rf->dma_coherent = of_dma_is_coherent(pdev->dev.of_node);
	rf->irq = platform_get_irq_optional(pdev, 0);
	if (rf->irq == -ENXIO)
		rf->irq = -1;
	else if (rf->irq < 0)
		return rf->irq;

	if (rf->irq >= 0) {
		ret = devm_request_irq(&pdev->dev, rf->irq, radfft_irq, 0,
				       dev_name(&pdev->dev), rf);
		if (ret)
			return dev_err_probe(&pdev->dev, ret,
					     "failed to request IRQ\n");
	}

	cfg = radfft_readl(rf, RADFFT_REG_POINT_LOG2);
	rf->point_log2 = cfg & 0xff;
	rf->axi_data_bytes = (cfg >> 16) & 0xff;
	rf->max_burst_beats = radfft_readl(rf, RADFFT_REG_BURST_BEATS) & 0xff;
	cfg = radfft_readl(rf, RADFFT_REG_CAP0);
	rf->max_point_log2 = cfg & 0xff;
	rf->max_input_width = (cfg >> 8) & 0xff;
	rf->max_output_width = (cfg >> 16) & 0xff;
	rf->twiddle_width = (cfg >> 24) & 0xff;
	cfg = radfft_readl(rf, RADFFT_REG_CAP1);
	rf->supported_radix = cfg & 0xff;
	rf->max_multiplier_lanes = (cfg >> 8) & 0xff;

	if (!rf->max_point_log2)
		rf->max_point_log2 = rf->point_log2;
	if (!rf->max_input_width)
		rf->max_input_width = 32;
	if (!rf->max_output_width)
		rf->max_output_width = 32;
	if (!rf->twiddle_width)
		rf->twiddle_width = 16;
	if (!rf->supported_radix)
		rf->supported_radix = BIT(0);
	if (!rf->max_multiplier_lanes)
		rf->max_multiplier_lanes = 16;

	if (radfft_readl(rf, RADFFT_REG_MAGIC) != RADFFT_MAGIC)
		dev_warn(&pdev->dev, "unexpected RADFFT magic value\n");

	rf->miscdev.minor = MISC_DYNAMIC_MINOR;
	rf->miscdev.name = devm_kasprintf(&pdev->dev, GFP_KERNEL, "%s",
					  dev_name(&pdev->dev));
	if (!rf->miscdev.name)
		return -ENOMEM;
	rf->miscdev.fops = &radfft_fops;
	rf->miscdev.parent = &pdev->dev;

	ret = misc_register(&rf->miscdev);
	if (ret)
		return dev_err_probe(&pdev->dev, ret,
				     "failed to register misc device\n");

	platform_set_drvdata(pdev, rf);
	dev_info(&pdev->dev,
		 "registered buffer phys=%pa size=%pa coherent=%d irq=%d\n",
		 &rf->buf_phys, &rf->buf_size, rf->dma_coherent, rf->irq);

	return 0;
}

static int radfft_remove(struct platform_device *pdev)
{
	struct raddsp_radfft_ddr_dev *rf = platform_get_drvdata(pdev);

	misc_deregister(&rf->miscdev);
	return 0;
}

static const struct of_device_id radfft_of_match[] = {
	{ .compatible = "rad,raddsp-axis-radfft-ddr-1.0" },
	{ .compatible = "rad,raddsp-axis-radfft-ddr" },
	{ }
};
MODULE_DEVICE_TABLE(of, radfft_of_match);

static struct platform_driver radfft_driver = {
	.probe = radfft_probe,
	.remove = radfft_remove,
	.driver = {
		.name = "raddsp-radfft-ddr",
		.of_match_table = radfft_of_match,
	},
};
module_platform_driver(radfft_driver);

MODULE_AUTHOR("RADHDL contributors");
MODULE_DESCRIPTION("RADHDL RADDsp DDR-backed RADFFT driver");
MODULE_LICENSE("Dual MIT/GPL");
