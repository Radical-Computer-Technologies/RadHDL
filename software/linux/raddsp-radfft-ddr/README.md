# RADDsp RADFFT DDR Linux Driver

This is a draft platform driver for the DDR-backed `raddsp_axis_radfft_ddr`
core. It is intentionally standalone for now, so it can later be consumed by a
Buildroot package, a PetaLinux layer, or an in-tree kernel integration.

## Interface

- AXI-Lite register space is mapped from the device-tree `reg` resource.
- The sample buffer is mapped from a `reserved-memory` node referenced by
  `memory-region`.
- Userspace opens the misc device, uses IOCTLs for control/status, and uses
  `mmap()` to access the reserved DDR buffer.

Current HDL modes:

- `RADDSP_RADFFT_DDR_MODE_AXIS_TO_DDR`: stream AXIS input into DDR using AXI4
  bursts.
- `RADDSP_RADFFT_DDR_MODE_DDR_TO_AXIS`: read DDR using AXI4 bursts and stream it
  out over AXIS.
- `RADDSP_RADFFT_DDR_MODE_MEM_TO_MEM_FFT`: load the active twiddle table from
  DDR, read one FFT frame from DDR, execute the configured RADFFT core, and
  write the result back to DDR.

Reserved future modes:

- `RADDSP_RADFFT_DDR_MODE_AXIS_TO_AXIS_FFT`

FFT mode requires `struct raddsp_radfft_ddr_config.twiddle_addr` to point inside
the same reserved-memory region. The current HDL layout is one twiddle per AXI
beat. For 16-bit coefficients on a 64-bit AXI data bus, the low 32 bits contain
`{twiddle_re[15:0], twiddle_im[15:0]}` and the upper 32 bits are ignored.

The core is self-describing through read-only AXI-Lite capability registers.
The driver probes maximum point log2, maximum real/imag input width, maximum
real/imag output width, twiddle width, supported radix modes, AXI data bytes,
maximum burst length, and multiplier-lane ceiling at probe time. Device tree
only needs to describe the register aperture, IRQ, and reserved-memory region.
Runtime config selects active point log2, radix, sample widths, and multiplier
lane mode through IOCTL; unsupported combinations are rejected before start.
Runtime flags select the FFT data route:

- no flags: DDR input to DDR output
- `RADDSP_RADFFT_DDR_FLAG_FFT_SRC_AXIS`: AXIS input to DDR output
- `RADDSP_RADFFT_DDR_FLAG_FFT_DST_AXIS`: DDR input to AXIS output
- both flags: AXIS input to AXIS output

The shared FFT engine latches active point log2 at frame start and supports
runtime frame lengths up to the compiled maximum point count.

## Device Tree Sketch

Zynq UltraScale+ example:

```dts
reserved-memory {
	#address-cells = <2>;
	#size-cells = <2>;
	ranges;

	radfft0_buf: radfft-buffer@70000000 {
		compatible = "shared-dma-pool";
		reg = <0x0 0x70000000 0x0 0x04000000>;
		no-map;
	};
};

radfft0: fft@a0000000 {
	compatible = "rad,raddsp-axis-radfft-ddr-1.0";
	reg = <0x0 0xa0000000 0x0 0x10000>;
	interrupt-parent = <&gic>;
	interrupts = <0 89 4>;
	memory-region = <&radfft0_buf>;
	dma-coherent;
};
```

Zynq-7000 example:

```dts
reserved-memory {
	#address-cells = <1>;
	#size-cells = <1>;
	ranges;

	radfft0_buf: radfft-buffer@1c000000 {
		compatible = "shared-dma-pool";
		reg = <0x1c000000 0x04000000>;
		no-map;
	};
};

radfft0: fft@43c00000 {
	compatible = "rad,raddsp-axis-radfft-ddr-1.0";
	reg = <0x43c00000 0x10000>;
	interrupt-parent = <&intc>;
	interrupts = <0 59 4>;
	memory-region = <&radfft0_buf>;
};
```

`no-map` does not imply coherency. It only prevents the kernel from creating a
normal linear mapping for the reserved DDR region. The completion interrupt only
tells software that the PL transaction is done; it does not invalidate CPU cache
lines. For non-coherent ports, the driver maps the userspace buffer with
`remap_pfn_range()` and `pgprot_writecombine()`, so userspace sees the buffer as
IO-like, non-normal-cached memory.

Do not add `dma-coherent` on Zynq-7000 HP-port designs unless the platform is
actually coherent. Zynq UltraScale+ designs may use `dma-coherent` only when the
chosen PL port and interconnect configuration are coherent.

## Build

```sh
make KDIR=/path/to/kernel/build
make examples CROSS_COMPILE=aarch64-linux-gnu-
```

The public UAPI is in `raddsp_radfft_ddr.h`.

## Example

The `examples/radfft_ddr_ctl.c` utility shows the intended userspace flow:

1. Open the misc device.
2. Query buffer/register metadata with `RADDSP_RADFFT_DDR_IOC_GET_INFO`.
3. `mmap()` the reserved DDR buffer.
4. Configure physical buffer addresses, optional twiddle address, and transfer
   length.
5. Start the core, wait for IRQ/polled completion, and read status.

Example command:

```sh
./examples/radfft_ddr_ctl /dev/a0000000.fft 1 4096
```
