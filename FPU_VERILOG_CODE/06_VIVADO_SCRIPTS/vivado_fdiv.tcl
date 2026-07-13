set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. 03_DIV_AXI]]

create_project FDIV_SIM [file join $script_dir vivado_fdiv_sim] \
    -part xck26-sfvc784-2LV-c -force
add_files [list \
    [file join $rtl_dir fdiv_top.v] \
    [file join $rtl_dir fdiv_mant_divider.v] \
    [file join $rtl_dir fdiv_axi_lite.v] \
]
add_files -fileset sim_1 [file join $rtl_dir fdiv_tb.v]
set_property top fdiv_tb [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
