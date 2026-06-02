#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/uaccess.h>

#define RAD_ILA_REG_ID          0x00
#define RAD_ILA_REG_VERSION     0x04
#define RAD_ILA_REG_CONTROL     0x08
#define RAD_ILA_REG_STATUS      0x0c
#define RAD_ILA_REG_TRIG_MASK   0x10
#define RAD_ILA_REG_TRIG_VALUE  0x14
#define RAD_ILA_REG_PRETRIG     0x18
#define RAD_ILA_REG_POSTTRIG    0x1c
#define RAD_ILA_REG_DATA_INDEX  0x20
#define RAD_ILA_REG_DATA_VALUE  0x24
#define RAD_ILA_REG_SAMPLE_NOW  0x28
#define RAD_ILA_REG_EVENT_NOW   0x2c
#define RAD_ILA_REG_WIDTHS      0x30
#define RAD_ILA_REG_DATA_VALUE_HI 0x34

#define RAD_ILA_IOC_MAGIC       'N'
#define RAD_ILA_IOC_ARM         _IO(RAD_ILA_IOC_MAGIC, 1)
#define RAD_ILA_IOC_CLEAR       _IO(RAD_ILA_IOC_MAGIC, 2)
#define RAD_ILA_IOC_SW_TRIGGER  _IO(RAD_ILA_IOC_MAGIC, 3)
#define RAD_ILA_IOC_SET_CONFIG  _IOW(RAD_ILA_IOC_MAGIC, 4, struct rad_ila_config)
#define RAD_ILA_IOC_GET_STATUS  _IOR(RAD_ILA_IOC_MAGIC, 5, struct rad_ila_status)

struct rad_ila_config {
	u32 trig_mask;
	u32 trig_value;
	u32 pretrig;
	u32 posttrig;
	u32 control;
};

struct rad_ila_status {
	u32 id;
	u32 version;
	u32 control;
	u32 status;
	u32 sample_now;
	u32 event_now;
	u32 widths;
};

struct rad_ila_dev {
	void __iomem *regs;
	struct device *dev;
	struct cdev cdev;
	dev_t devt;
	struct class *class;
};

static struct rad_ila_dev *g_ila;

static int rad_ila_open(struct inode *inode, struct file *file)
{
	file->private_data = g_ila;
	return 0;
}

static ssize_t rad_ila_read(struct file *file, char __user *buf, size_t len, loff_t *ppos)
{
	struct rad_ila_dev *ila = file->private_data;
	u32 index = (u32)(*ppos / sizeof(u32));
	u32 sample_width;
	u32 words_per_sample;
	u32 sample_index;
	u32 word_index;
	u32 value;

	if (!ila || !ila->regs)
		return -ENODEV;
	if (len < sizeof(value))
		return 0;
	sample_width = ioread32(ila->regs + RAD_ILA_REG_WIDTHS) >> 16;
	words_per_sample = DIV_ROUND_UP(sample_width ? sample_width : 32, 32);
	if (!words_per_sample)
		words_per_sample = 1;
	sample_index = index / words_per_sample;
	word_index = index % words_per_sample;
	if (sample_index >= 1024)
		return 0;

	iowrite32(sample_index, ila->regs + RAD_ILA_REG_DATA_INDEX);
	value = word_index ? ioread32(ila->regs + RAD_ILA_REG_DATA_VALUE_HI) :
			     ioread32(ila->regs + RAD_ILA_REG_DATA_VALUE);
	if (copy_to_user(buf, &value, sizeof(value)))
		return -EFAULT;
	*ppos += sizeof(value);
	return sizeof(value);
}

static long rad_ila_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	struct rad_ila_dev *ila = file->private_data;
	u32 ctl;

	if (!ila || !ila->regs)
		return -ENODEV;

	ctl = ioread32(ila->regs + RAD_ILA_REG_CONTROL);
	switch (cmd) {
	case RAD_ILA_IOC_ARM:
		iowrite32(ctl | 0x1, ila->regs + RAD_ILA_REG_CONTROL);
		return 0;
	case RAD_ILA_IOC_CLEAR:
		iowrite32(ctl | 0x4, ila->regs + RAD_ILA_REG_CONTROL);
		return 0;
	case RAD_ILA_IOC_SW_TRIGGER:
		iowrite32(ctl | 0x2, ila->regs + RAD_ILA_REG_CONTROL);
		return 0;
	case RAD_ILA_IOC_SET_CONFIG: {
		struct rad_ila_config cfg;

		if (copy_from_user(&cfg, (void __user *)arg, sizeof(cfg)))
			return -EFAULT;
		iowrite32(cfg.trig_mask, ila->regs + RAD_ILA_REG_TRIG_MASK);
		iowrite32(cfg.trig_value, ila->regs + RAD_ILA_REG_TRIG_VALUE);
		iowrite32(cfg.pretrig, ila->regs + RAD_ILA_REG_PRETRIG);
		iowrite32(cfg.posttrig, ila->regs + RAD_ILA_REG_POSTTRIG);
		iowrite32(cfg.control, ila->regs + RAD_ILA_REG_CONTROL);
		return 0;
	}
	case RAD_ILA_IOC_GET_STATUS: {
		struct rad_ila_status status;

		status.id = ioread32(ila->regs + RAD_ILA_REG_ID);
		status.version = ioread32(ila->regs + RAD_ILA_REG_VERSION);
		status.control = ioread32(ila->regs + RAD_ILA_REG_CONTROL);
		status.status = ioread32(ila->regs + RAD_ILA_REG_STATUS);
		status.sample_now = ioread32(ila->regs + RAD_ILA_REG_SAMPLE_NOW);
		status.event_now = ioread32(ila->regs + RAD_ILA_REG_EVENT_NOW);
		status.widths = ioread32(ila->regs + RAD_ILA_REG_WIDTHS);
		if (copy_to_user((void __user *)arg, &status, sizeof(status)))
			return -EFAULT;
		return 0;
	}
	default:
		return -ENOTTY;
	}
}

static const struct file_operations rad_ila_fops = {
	.owner = THIS_MODULE,
	.open = rad_ila_open,
	.read = rad_ila_read,
	.unlocked_ioctl = rad_ila_ioctl,
	.llseek = default_llseek,
};

static int rad_ila_probe(struct platform_device *pdev)
{
	struct rad_ila_dev *ila;
	struct resource *res;
	int ret;

	ila = devm_kzalloc(&pdev->dev, sizeof(*ila), GFP_KERNEL);
	if (!ila)
		return -ENOMEM;
	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	ila->regs = devm_ioremap_resource(&pdev->dev, res);
	if (IS_ERR(ila->regs))
		return PTR_ERR(ila->regs);
	ila->dev = &pdev->dev;

	ret = alloc_chrdev_region(&ila->devt, 0, 1, "rad-axi-ila");
	if (ret)
		return ret;
	cdev_init(&ila->cdev, &rad_ila_fops);
	ret = cdev_add(&ila->cdev, ila->devt, 1);
	if (ret)
		goto err_unregister;
	ila->class = class_create(THIS_MODULE, "rad-axi-ila");
	if (IS_ERR(ila->class)) {
		ret = PTR_ERR(ila->class);
		goto err_cdev;
	}
	device_create(ila->class, NULL, ila->devt, NULL, "rad-axi-ila");
	platform_set_drvdata(pdev, ila);
	g_ila = ila;
	dev_info(&pdev->dev, "Rad ILA id=0x%08x version=0x%08x\n",
		 ioread32(ila->regs + RAD_ILA_REG_ID),
		 ioread32(ila->regs + RAD_ILA_REG_VERSION));
	return 0;

err_cdev:
	cdev_del(&ila->cdev);
err_unregister:
	unregister_chrdev_region(ila->devt, 1);
	return ret;
}

static int rad_ila_remove(struct platform_device *pdev)
{
	struct rad_ila_dev *ila = platform_get_drvdata(pdev);

	device_destroy(ila->class, ila->devt);
	class_destroy(ila->class);
	cdev_del(&ila->cdev);
	unregister_chrdev_region(ila->devt, 1);
	if (g_ila == ila)
		g_ila = NULL;
	return 0;
}

static const struct of_device_id rad_ila_of_match[] = {
	{ .compatible = "rct,rad-axi-ila-1.0" },
	{ }
};
MODULE_DEVICE_TABLE(of, rad_ila_of_match);

static struct platform_driver rad_ila_driver = {
	.probe = rad_ila_probe,
	.remove = rad_ila_remove,
	.driver = {
		.name = "rad-axi-ila",
		.of_match_table = rad_ila_of_match,
	},
};
module_platform_driver(rad_ila_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Radical Computer Technologies LLC");
MODULE_DESCRIPTION("Rad ILA capture driver");
