proc init {cellpath otherInfo} {
    set cell [get_bd_cells -quiet $cellpath]
    if {$cell eq ""} {
        return
    }
}

proc post_config_ip {cellpath otherInfo} {
    set cell [get_bd_cells -quiet $cellpath]
    if {$cell eq ""} {
        return
    }
}
