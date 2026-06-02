namespace eval rad_debug_hub {
    variable manifest_schema "radfpga.debughub.manifest.v1"
    variable hub_vlnv "user.org:user:radila:1.0"
}

proc rad_debug_hub::json_escape {value} {
    set out ""
    foreach ch [split $value ""] {
        switch -- $ch {
            "\\" {append out "\\\\"}
            "\"" {append out "\\\""}
            "\n" {append out "\\n"}
            "\r" {append out "\\r"}
            "\t" {append out "\\t"}
            default {append out $ch}
        }
    }
    return $out
}

proc rad_debug_hub::json_string {value} {
    return "\"[json_escape $value]\""
}

proc rad_debug_hub::cell_vlnv {cell} {
    if {[catch {set vlnv [get_property VLNV $cell]}]} {
        return ""
    }
    return $vlnv
}

proc rad_debug_hub::config_value {cell name default_value} {
    if {[catch {set value [get_property CONFIG.$name $cell]}] || $value eq ""} {
        return $default_value
    }
    return $value
}

proc rad_debug_hub::pin_width {pin default_width} {
    if {$pin eq ""} {
        return $default_width
    }
    if {![catch {set left [get_property LEFT $pin]}] && ![catch {set right [get_property RIGHT $pin]}]} {
        if {$left ne "" && $right ne ""} {
            return [expr {abs(int($left) - int($right)) + 1}]
        }
    }
    return $default_width
}

proc rad_debug_hub::pin_net_name {pin} {
    set nets [get_bd_nets -quiet -of_objects $pin]
    if {[llength $nets] == 0} {
        return ""
    }
    return [get_property NAME [lindex $nets 0]]
}

proc rad_debug_hub::concat_source_cell {pin} {
    set nets [get_bd_nets -quiet -of_objects $pin]
    if {[llength $nets] == 0} {
        return ""
    }

    foreach other_pin [get_bd_pins -quiet -of_objects [lindex $nets 0]] {
        if {$other_pin eq $pin} {
            continue
        }
        if {[get_property NAME $other_pin] ne "dout"} {
            continue
        }
        set parent [get_bd_cells -quiet -of_objects $other_pin]
        if {$parent eq ""} {
            continue
        }
        if {[string first "xilinx.com:ip:xlconcat:" [cell_vlnv $parent]] == 0} {
            return $parent
        }
    }
    return ""
}

proc rad_debug_hub::concat_signals {concat_cell kind} {
    set signals {}
    set ports [config_value $concat_cell NUM_PORTS 0]
    set offset 0
    for {set idx 0} {$idx < $ports} {incr idx} {
        set pin [get_bd_pins -quiet $concat_cell/In$idx]
        set width [config_value $concat_cell IN${idx}_WIDTH [pin_width $pin 1]]
        set net [pin_net_name $pin]
        if {$net eq ""} {
            set net "unconnected_$kind$idx"
        }
        lappend signals [dict create \
            name $net \
            width $width \
            kind $kind \
            index $idx \
            lsb $offset \
            msb [expr {$offset + int($width) - 1}] \
        ]
        incr offset $width
    }
    return $signals
}

proc rad_debug_hub::direct_signal {cell port kind width} {
    set pin [get_bd_pins -quiet $cell/$port]
    set net [pin_net_name $pin]
    if {$net eq ""} {
        set net "$cell/$port"
    }
    return [list [dict create \
        name $net \
        width [pin_width $pin $width] \
        kind $kind \
        index 0 \
        lsb 0 \
        msb [expr {$width - 1}] \
    ]]
}

proc rad_debug_hub::core_signals {cell} {
    set sample_width [config_value $cell SAMPLE_WIDTH 32]
    set event_width [config_value $cell EVENT_WIDTH 8]
    set signals {}

    set sample_pin [get_bd_pins -quiet $cell/sample_i]
    set sample_concat [concat_source_cell $sample_pin]
    if {$sample_concat ne ""} {
        set signals [concat $signals [concat_signals $sample_concat sample]]
    } else {
        set signals [concat $signals [direct_signal $cell sample_i sample $sample_width]]
    }

    set event_pin [get_bd_pins -quiet $cell/event_i]
    set event_concat [concat_source_cell $event_pin]
    if {$event_concat ne ""} {
        set signals [concat $signals [concat_signals $event_concat event]]
    } else {
        set signals [concat $signals [direct_signal $cell event_i event $event_width]]
    }

    return $signals
}

proc rad_debug_hub::discover_cores {} {
    variable hub_vlnv
    set cores {}
    foreach cell [get_bd_cells -hier -quiet *] {
        set vlnv [cell_vlnv $cell]
        set name [get_property NAME $cell]
        if {[string first $hub_vlnv $vlnv] == 0 || [string match -nocase "*radila*" $name] || [string match -nocase "*rad_debug_hub*" $name]} {
            lappend cores $cell
        }
    }
    return [lsort -unique $cores]
}

proc rad_debug_hub::ensure_hub {{cell_name rad_debug_hub_0}} {
    variable hub_vlnv
    set cores [discover_cores]
    if {[llength $cores] > 0} {
        return [lindex $cores 0]
    }

    set hub [create_bd_cell -type ip -vlnv $hub_vlnv $cell_name]
    hide_debug_plumbing [list $hub]
    return $hub
}

proc rad_debug_hub::hide_one {object} {
    set props [list_property $object]
    foreach prop {IS_HIDDEN HIDDEN BD_IS_HIDDEN RAD_DEBUG_HIDDEN} {
        if {[lsearch -exact $props $prop] >= 0} {
            catch {set_property $prop true $object}
        }
    }
}

proc rad_debug_hub::hide_debug_plumbing {{objects ""}} {
    if {$objects eq ""} {
        set objects {}
        foreach cell [discover_cores] {
            lappend objects $cell
            foreach pin {sample_i event_i irq_o s00_axi_aclk s00_axi_aresetn} {
                set bd_pin [get_bd_pins -quiet $cell/$pin]
                if {$bd_pin ne ""} {
                    set nets [get_bd_nets -quiet -of_objects $bd_pin]
                    foreach net $nets {
                        lappend objects $net
                    }
                }
            }
        }
        foreach cell [get_bd_cells -hier -quiet *] {
            set name [get_property NAME $cell]
            if {[string match "*radila_*concat*" $name] || [string match "*rad_debug_hub_*" $name]} {
                lappend objects $cell
            }
        }
    }

    foreach object [lsort -unique $objects] {
        hide_one $object
    }
}

proc rad_debug_hub::dict_json {d indent} {
    set parts {}
    dict for {key value} $d {
        if {[string is integer -strict $value]} {
            set encoded $value
        } else {
            set encoded [json_string $value]
        }
        lappend parts "[string repeat " " $indent][json_string $key]: $encoded"
    }
    return "{\n[join $parts ",\n"]\n[string repeat " " [expr {$indent - 2}]]}"
}

proc rad_debug_hub::signals_json {signals indent} {
    set parts {}
    foreach sig $signals {
        lappend parts [dict_json $sig [expr {$indent + 2}]]
    }
    return "[string repeat " " $indent]\[\n[join $parts ",\n"]\n[string repeat " " $indent]\]"
}

proc rad_debug_hub::emit_manifest {path} {
    variable manifest_schema
    set cores [discover_cores]
    set design_name [get_property NAME [current_bd_design]]
    file mkdir [file dirname $path]

    set fh [open $path w]
    puts $fh "{"
    puts $fh "  \"schema\": [json_string $manifest_schema],"
    puts $fh "  \"design\": [json_string $design_name],"
    puts $fh "  \"cores\": \["

    set idx 0
    foreach cell $cores {
        set comma [expr {$idx + 1 < [llength $cores] ? "," : ""}]
        set signals [core_signals $cell]
        puts $fh "    {"
        puts $fh "      \"name\": [json_string [get_property NAME $cell]],"
        puts $fh "      \"path\": [json_string $cell],"
        puts $fh "      \"vlnv\": [json_string [cell_vlnv $cell]],"
        puts $fh "      \"sample_width\": [config_value $cell SAMPLE_WIDTH 32],"
        puts $fh "      \"event_width\": [config_value $cell EVENT_WIDTH 8],"
        puts $fh "      \"cmd_lanes\": [config_value $cell CMD_LANES 4],"
        puts $fh "      \"vendor_tag\": [json_string [config_value $cell VENDOR_TAG XILINX]],"
        puts $fh "      \"product_series_tag\": [json_string [config_value $cell PRODUCT_SERIES_TAG 7SERIES]],"
        puts $fh "      \"debug_bus\": [json_string [config_value $cell G_DEBUG_BUS AXI_LITE]],"
        puts $fh "      \"signals\": [string range [signals_json $signals 6] 6 end]"
        puts $fh "    }$comma"
        incr idx
    }

    puts $fh "  \]"
    puts $fh "}"
    close $fh
    return $path
}
