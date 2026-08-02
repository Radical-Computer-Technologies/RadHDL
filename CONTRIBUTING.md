# Contributing to RadHDL

RadHDL is the open HDL/IP library for Radical Computer Technologies. The
project is VHDL-first and focuses on portable, reusable cores that can still map
cleanly onto real FPGA vendor resources.

## Development Flow

1. Create a feature branch from `main`.
2. Keep changes scoped to one subsystem when possible: primitives, RADIF,
   DSP, debug, board examples, or documentation.
3. Add or update a focused testbench for any behavioral change.
4. Run the relevant GHDL or vendor simulation before opening a pull request.
5. Include the tool version used for FPGA builds, synthesis reports, or timing
   evidence when a change affects implementation results.

## HDL Style

- Prefer VHDL-2008 for new reusable HDL.
- Keep entity names stable and descriptive.
- Keep reset, clock-domain, and handshaking behavior explicit.
- Do not hide vendor-specific behavior inside board-local code when a reusable
  wrapper belongs in `common/hdl/src`.
- Avoid generated tool output in commits. Reports can be summarized in docs;
  raw `.rpt`, `.log`, `.jou`, `.wdb`, object, and build-cache files should stay
  out of the repository.

## Primitive Policy

RadHDL primitives exist to make portability concrete, not aspirational.

- Use vendor wrapper entities for FPGA-specific RAM, FIFO, DSP, PLL, and CDC
  primitives.
- For Xilinx targets, wrap XPM or documented primitive structures behind
  RadHDL interfaces.
- For Lattice and Gowin targets, instantiate explicit vendor primitives where
  the vendor provides them. Do not rely on inference when the design intent is
  a primitive-backed resource.
- Generic models are allowed for simulation, documentation, or unsupported
  targets, but they should be clearly named and covered by equivalence tests.
- New vendor paths should reuse the same top-level RadHDL primitive interface
  whenever possible.

## Test Expectations

Use the narrowest test that proves the change:

```sh
scripts/radhdl_sim_matrix.py --mode generic-ghdl
```

For Xilinx primitive checks:

```sh
scripts/radhdl_sim_matrix.py --mode xilinx-xsim --vivado-version 2024.1
```

For the FPiGA audio shared-math top-level simulation:

```sh
RADHDL_AUDIO_FAST_SMOKE=1 \
  projects/examples/fpiga_audio_hat_shared_math/sim/run_audio_hat_shared_math_top_ghdl.sh
```

Use `RADHDL_AUDIO_DEBUG_I2C_SMOKE=1` only when intentionally working on the
RadDebugHub I2C readback path.

## Pull Request Notes

Good pull requests include:

- A short summary of the behavioral or implementation change.
- Test commands and pass/fail results.
- Tool versions for vendor synthesis or simulation.
- Updated docs when public interfaces, registers, package structure, or build
  flow changes.

Issues and discussions should include the target FPGA family, toolchain version,
simulation command, and any relevant timing/resource report summary.
