#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "hdl" / "radhdl_library.tcl"

RADHDL_API = [
    "hdl/radhdl/src/dsp.vhd",
    "hdl/radhdl/src/dsp_comms.vhd",
    "hdl/radhdl/src/dsp_detection.vhd",
    "hdl/radhdl/src/dsp_filter.vhd",
    "hdl/radhdl/src/dsp_matrix.vhd",
    "hdl/radhdl/src/dsp_transform.vhd",
    "hdl/radhdl/src/interfaces.vhd",
    "hdl/radhdl/src/interfaces_axi.vhd",
    "hdl/radhdl/src/interfaces_i2s.vhd",
    "hdl/radhdl/src/interfaces_i2c.vhd",
    "hdl/radhdl/src/interfaces_regbank.vhd",
    "hdl/radhdl/src/interfaces_smi.vhd",
    "hdl/radhdl/src/interfaces_spi.vhd",
    "hdl/radhdl/src/interfaces_uart.vhd",
    "hdl/radhdl/src/debug.vhd",
    "hdl/radhdl/src/dsp_context.vhd",
    "hdl/radhdl/src/interfaces_context.vhd",
    "hdl/radhdl/src/debug_context.vhd",
    "hdl/radhdl/src/radhdl_context.vhd",
]


COMMON_PROTOCOL = [
    "common/hdl/src/radhdl_axi_pkg.vhd",
    "common/hdl/src/radhdl_axis_pkg.vhd",
    "common/hdl/src/radhdl_spi_pkg.vhd",
]


DEBUG_RADILA = [
    "debug/radila/hdl/radila/radila_core.vhd",
    "debug/radila/hdl/radila/raddebughub.vhd",
]

DSP_RADDSP_RAW = [
    "dsp/hdl/raddsp/src/raddsp_axis_pkg.vhd",
    "dsp/hdl/raddsp/src/zc_reference_pkg.vhd",
    "dsp/hdl/raddsp/src/cordic_atan_pkg.vhd",
    "dsp/hdl/raddsp/src/raddsp_fft_twiddle_pkg.vhd",
    "dsp/hdl/raddsp/src/fft_tdp_ram.vhd",
    "dsp/hdl/raddsp/src/raddsp_fft_twiddle_rom.vhd",
    "dsp/hdl/raddsp/src/raddsp_sqrt_u32.vhd",
    "dsp/hdl/raddsp/src/raddsp_xilinx_dsp48_mul.vhd",
    "dsp/hdl/raddsp/src/raddsp_xilinx_dsp48_square_seq.vhd",
    "dsp/hdl/raddsp/src/raddsp_xilinx_dsp48_wide_mul.vhd",
    "dsp/hdl/raddsp/src/cordic_atan2.vhd",
    "dsp/hdl/raddsp/src/fft_radix2_batch_core.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_gain.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_mix2.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_one_pole_lowpass.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_fir.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_biquad.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_dds.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_am_iq_modulator.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_am_iq_demodulator.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_float_to_fixed.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_fixed_to_float.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_iq_magnitude_sq.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_frame_stats.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_fft_fingerprint.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_fingerprint_matcher.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_matrix_elementwise.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_matrix_dot.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_fft_bin_product.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_radfft_batch.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_radfft_radix2_tdp.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_radfft_radix4_tdp.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_radfft_parallel8.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_radfft_iterative.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_radfft_streaming.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_radfft.vhd",
    "dsp/hdl/raddsp/src/raddsp_axis_radfft_ddr.vhd",
    "dsp/hdl/raddsp/src/zc_cross_correlator.vhd",
    "dsp/hdl/raddsp/src/zc_peak_detector.vhd",
    "dsp/hdl/raddsp/src/zc_chirp_frame_detector.vhd",
    "dsp/hdl/raddsp/wrappers/raddsp_zc_chirp_frame_detector.vhd",
    "dsp/hdl/raddsp/wrappers/raddsp_cordic_atan2.vhd",
    "dsp/hdl/raddsp/wrappers/raddsp_fft_radix2_batch_core.vhd",
]

DSP_RADDSP_XCI = [
    "dsp/hdl/xci/raddsp_cordic_atan2_0/raddsp_cordic_atan2_0.xci",
    "dsp/hdl/xci/raddsp_fft_radix2_batch_core_0/raddsp_fft_radix2_batch_core_0.xci",
    "dsp/hdl/xci/raddsp_zc_chirp_frame_detector_0/raddsp_zc_chirp_frame_detector_0.xci",
]

DSP_RADDSP_XCI_VHDL = [
    "dsp/hdl/xci/raddsp_zc_chirp_frame_detector_0/src/zc_reference_pkg.vhd",
    "dsp/hdl/xci/raddsp_zc_chirp_frame_detector_0/src/zc_chirp_frame_detector.vhd",
    "dsp/hdl/xci/raddsp_zc_chirp_frame_detector_0/src/raddsp_zc_chirp_frame_detector.vhd",
    "dsp/hdl/xci/raddsp_zc_chirp_frame_detector_0/synth/raddsp_zc_chirp_frame_detector_0.vhd",
    "dsp/hdl/xci/raddsp_cordic_atan2_0/src/cordic_atan_pkg.vhd",
    "dsp/hdl/xci/raddsp_cordic_atan2_0/src/cordic_atan2.vhd",
    "dsp/hdl/xci/raddsp_cordic_atan2_0/src/raddsp_cordic_atan2.vhd",
    "dsp/hdl/xci/raddsp_cordic_atan2_0/synth/raddsp_cordic_atan2_0.vhd",
    "dsp/hdl/xci/raddsp_fft_radix2_batch_core_0/src/fft_tdp_ram.vhd",
    "dsp/hdl/xci/raddsp_fft_radix2_batch_core_0/src/fft_radix2_batch_core.vhd",
    "dsp/hdl/xci/raddsp_fft_radix2_batch_core_0/src/raddsp_fft_radix2_batch_core.vhd",
    "dsp/hdl/xci/raddsp_fft_radix2_batch_core_0/synth/raddsp_fft_radix2_batch_core_0.vhd",
]

INTERFACES_RADIF = [
    "interfaces/hdl/radif/src/radif_pkg.vhd",
    "interfaces/hdl/radif/src/radif_reg_bank.vhd",
    "interfaces/hdl/radif/src/radif_reg_interconnect.vhd",
    "interfaces/hdl/radif/src/radif_gpio_reg_block.vhd",
    "interfaces/hdl/radif/src/radif_irq_controller.vhd",
    "interfaces/hdl/radif/src/radif_axi_lite_to_reg.vhd",
    "interfaces/hdl/radif/src/radif_uart_to_reg.vhd",
    "interfaces/hdl/radif/src/radif_i2s_axis.vhd",
    "interfaces/hdl/radif/src/radif_reg_to_i2c_master.vhd",
    "interfaces/hdl/radif/src/radif_reg_to_spi_master.vhd",
    "interfaces/hdl/radif/src/radif_spi_slave_to_reg.vhd",
    "interfaces/hdl/radif/src/radif_qspi_slave_to_reg.vhd",
    "interfaces/hdl/radif/src/radif_i2c_slave_to_reg.vhd",
    "interfaces/hdl/radif/src/radif_smi16_to_reg.vhd",
    "interfaces/hdl/radif/src/radif_axi4_axis_dma.vhd",
    "interfaces/hdl/radif/src/radif_spi_axi_master.vhd",
]


def tcl_list(paths):
    items = " \\\n".join(f"        [file join $::RadHDL::ROOT {' '.join(p.split('/'))}]" for p in paths)
    return f"[list \\\n{items} \\\n    ]"


def write_library():
    text = f"""# Generated by scripts/generate_radhdl_library.py. Do not hand-edit.

namespace eval ::RadHDL {{
    variable ROOT [file normalize [file join [file dirname [info script]] ..]]
    variable RADHDL_API_FILES {tcl_list(RADHDL_API)}
    variable COMMON_PROTOCOL_FILES {tcl_list(COMMON_PROTOCOL)}
    variable DEBUG_RADILA_FILES {tcl_list(DEBUG_RADILA)}
    variable DSP_RADDSP_RAW_FILES {tcl_list(DSP_RADDSP_RAW)}
    variable DSP_RADDSP_XCI_FILES {tcl_list(DSP_RADDSP_XCI)}
    variable DSP_RADDSP_XCI_VHDL_FILES {tcl_list(DSP_RADDSP_XCI_VHDL)}
    variable INTERFACES_RADIF_FILES {tcl_list(INTERFACES_RADIF)}
    variable DSP_RADDSP_IP_REPO [file join $ROOT dsp hdl iprepo]

    proc files {{library}} {{
        variable DEBUG_RADILA_FILES
        variable RADHDL_API_FILES
        variable COMMON_PROTOCOL_FILES
        variable DSP_RADDSP_RAW_FILES
        variable DSP_RADDSP_XCI_FILES
        variable DSP_RADDSP_XCI_VHDL_FILES
        variable INTERFACES_RADIF_FILES

        switch -- $library {{
            radhdl.api {{ return $RADHDL_API_FILES }}
            radhdl.protocol {{ return $COMMON_PROTOCOL_FILES }}
            protocol {{ return $COMMON_PROTOCOL_FILES }}
            radhdl.all {{ return [concat $COMMON_PROTOCOL_FILES $DSP_RADDSP_RAW_FILES $INTERFACES_RADIF_FILES $DEBUG_RADILA_FILES $RADHDL_API_FILES] }}
            all {{ return [concat $COMMON_PROTOCOL_FILES $DSP_RADDSP_RAW_FILES $INTERFACES_RADIF_FILES $DEBUG_RADILA_FILES $RADHDL_API_FILES] }}
            debug.radila {{ return $DEBUG_RADILA_FILES }}
            debug {{ return $DEBUG_RADILA_FILES }}
            dsp.raddsp.raw {{ return [concat $COMMON_PROTOCOL_FILES $DSP_RADDSP_RAW_FILES] }}
            dsp.raw {{ return [concat $COMMON_PROTOCOL_FILES $DSP_RADDSP_RAW_FILES] }}
            dsp.raddsp.xci {{ return $DSP_RADDSP_XCI_FILES }}
            dsp.xci {{ return $DSP_RADDSP_XCI_FILES }}
            dsp.raddsp.xci_vhdl {{ return $DSP_RADDSP_XCI_VHDL_FILES }}
            dsp.xci_vhdl {{ return $DSP_RADDSP_XCI_VHDL_FILES }}
            interfaces.radif {{ return [concat $COMMON_PROTOCOL_FILES $INTERFACES_RADIF_FILES] }}
            interfaces {{ return [concat $COMMON_PROTOCOL_FILES $INTERFACES_RADIF_FILES] }}
            default {{ error "unknown RadHDL library '$library'" }}
        }}
    }}

    proc existing_files {{library}} {{
        set out {{}}
        foreach f [files $library] {{
            if {{[file exists $f]}} {{
                lappend out $f
            }}
        }}
        return $out
    }}

    proc require_files {{library}} {{
        set missing {{}}
        set out {{}}
        foreach f [files $library] {{
            if {{[file exists $f]}} {{
                lappend out $f
            }} else {{
                lappend missing $f
            }}
        }}
        if {{[llength $missing] > 0}} {{
            error "missing RadHDL $library files: $missing"
        }}
        return $out
    }}

    proc ip_repo_paths {{args}} {{
        variable DSP_RADDSP_IP_REPO
        set paths {{}}
        foreach name $args {{
            switch -- $name {{
                dsp.raddsp - dsp {{ lappend paths $DSP_RADDSP_IP_REPO }}
                default {{ error "unknown RadHDL IP repo '$name'" }}
            }}
        }}
        return $paths
    }}

    proc add_files {{library args}} {{
        set files [require_files $library]
        if {{[llength $files] > 0}} {{
            uplevel 1 [list add_files {{*}}$args -norecurse $files]
        }}
        return $files
    }}
}}
"""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)


if __name__ == "__main__":
    write_library()
