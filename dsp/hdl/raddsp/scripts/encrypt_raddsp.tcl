source [file join [file dirname [info script]] raddsp_files.tcl]

file mkdir $raddsp_release_dir
raddsp_check_files $raddsp_src_files

foreach src_file $raddsp_src_files {
    set dst_file [file join $raddsp_release_dir "[file tail $src_file].enc"]
    file copy -force $src_file $dst_file
}

if {[info exists ::env(RADDSP_VIVADO_ENCRYPT_KEY)] && $::env(RADDSP_VIVADO_ENCRYPT_KEY) ne ""} {
    set raddsp_key_file [file normalize $::env(RADDSP_VIVADO_ENCRYPT_KEY)]
} else {
    set raddsp_key_file ""
    if {[info exists ::env(XILINX_VIVADO)] && $::env(XILINX_VIVADO) ne ""} {
        set pubkey_matches [lsort [glob -nocomplain [file join $::env(XILINX_VIVADO) data pubkey *active.vhd]]]
        if {[llength $pubkey_matches] > 0} {
            set raddsp_key_file [lindex $pubkey_matches end]
        }
    }
}

if {$raddsp_key_file eq "" || ![file exists $raddsp_key_file]} {
    puts "RADDSP_ENCRYPT_FAILED: no Vivado IEEE-1735 VHDL public key file found."
    puts "Set RADDSP_VIVADO_ENCRYPT_KEY or source Vivado settings so XILINX_VIVADO points at an install containing data/pubkey/*active.vhd."
    exit 2
}

set encrypt_cmd [list encrypt -key $raddsp_key_file -lang vhdl]
set encrypt_cmd [concat $encrypt_cmd $raddsp_release_files]
puts "Running raddsp Vivado encryption with key: $raddsp_key_file"
if {[catch {eval $encrypt_cmd} err]} {
    puts "RADDSP_ENCRYPT_FAILED: $err"
    puts "Vivado IEEE-1735 encryption requires the Vivado encryption license and a valid key file or embedded encryption pragmas."
    exit 2
}

puts "PASS raddsp encrypted release files written to $raddsp_release_dir"
