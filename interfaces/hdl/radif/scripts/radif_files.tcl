set radif_script_dir [file normalize [file dirname [info script]]]
set radif_hdl_dir [file normalize [file join $radif_script_dir ..]]
set radif_repo_dir [file normalize [file join $radif_hdl_dir .. .. ..]]
set radif_common_src_dir [file join $radif_repo_dir common hdl src]
set radif_src_dir [file join $radif_hdl_dir src]
set radif_tb_dir [file join $radif_hdl_dir testbenches]

set radif_src_files [list \
    [file join $radif_common_src_dir radhdl_axis_pkg.vhd] \
    [file join $radif_common_src_dir radhdl_spi_pkg.vhd] \
    [file join $radif_src_dir radif_pkg.vhd] \
    [file join $radif_src_dir radif_reg_bank.vhd] \
    [file join $radif_src_dir radif_reg_interconnect.vhd] \
    [file join $radif_src_dir radif_axi_lite_to_reg.vhd] \
    [file join $radif_src_dir radif_spi_slave_to_reg.vhd] \
    [file join $radif_src_dir radif_qspi_slave_to_reg.vhd] \
    [file join $radif_src_dir radif_i2c_slave_to_reg.vhd] \
    [file join $radif_src_dir radif_smi16_to_reg.vhd] \
    [file join $radif_src_dir radif_axi4_axis_dma.vhd] \
    [file join $radif_src_dir radif_spi_axi_master.vhd] \
]

set radif_tb_files [list \
    [file join $radif_tb_dir tb_radif_reg_bank.vhd] \
    [file join $radif_tb_dir tb_radif_reg_interconnect.vhd] \
    [file join $radif_tb_dir tb_radif_axi_lite_to_reg.vhd] \
    [file join $radif_tb_dir tb_radif_smi16_to_reg.vhd] \
    [file join $radif_tb_dir tb_radif_axi4_axis_dma.vhd] \
    [file join $radif_tb_dir tb_radif_interfaces_smoke.vhd] \
]

proc radif_check_files {files} {
    foreach f $files {
        if {![file exists $f]} {
            error "Missing radif file: $f"
        }
    }
}
