# Package the all-Verilog ADD/SUB/MUL AXI4-Lite block as a Vivado IP.
#
# Usage from the Vivado Tcl Console:
#   cd <path-to-tong-hop-FPU-vivado>/06_VIVADO_SCRIPTS
#   source package_fpu_axi_ip.tcl

set script_dir [file normalize [file dirname [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_dir [file join $script_dir vivado_fpu_axi_ip_pack]
set ip_repo_dir [file join $script_dir ip_repo]
set ip_root [file join $ip_repo_dir fpu_axi_wrapper_1_0]
set part_name xck26-sfvc784-2LV-c

create_project FPU_AXI_IP_PACK $project_dir -part $part_name -force

add_files -norecurse [list \
    [file join $root_dir 01_ADD_SUB fpu_add_sub_fixed.v] \
    [file join $root_dir 02_MUL fpu_mul.v] \
    [file join $root_dir 04_FPU_AXI_WRAPPER fp_addsub_axi_adapter.v] \
    [file join $root_dir 04_FPU_AXI_WRAPPER fpu_axi_wrapper_v1_0_S00_AXI.v] \
    [file join $root_dir 04_FPU_AXI_WRAPPER fpu_axi_wrapper_v1_0.v] \
]

set_property top fpu_axi_wrapper_v1_0 [get_filesets sources_1]
update_compile_order -fileset sources_1

ipx::package_project \
    -root_dir $ip_root \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -force

set core [ipx::current_core]
set_property name fpu_axi_wrapper $core
set_property display_name {FPU ADD-SUB-MUL AXI4-Lite} $core
set_property description {IEEE 754 binary32 ADD, SUB and MUL with AXI4-Lite interface.} $core
set_property version 1.0 $core

catch {ipx::infer_bus_interface S00_AXI xilinx.com:interface:aximm_rtl:1.0 $core}
catch {ipx::infer_bus_interface s00_axi_aclk xilinx.com:signal:clock_rtl:1.0 $core}
catch {ipx::infer_bus_interface s00_axi_aresetn xilinx.com:signal:reset_rtl:1.0 $core}
catch {ipx::associate_bus_interfaces -busif S00_AXI -clock s00_axi_aclk $core}

ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

puts "FPU AXI IP packaged at: $ip_root"
puts "Add this repository in Vivado: $ip_repo_dir"
