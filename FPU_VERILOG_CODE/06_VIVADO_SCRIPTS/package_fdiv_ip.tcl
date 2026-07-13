# Package the FDIV block as a Vivado IP.
#
# Usage from Vivado Tcl Console:
#   cd <path-to-tong-hop-FPU-vivado>/06_VIVADO_SCRIPTS
#   source package_fdiv_ip.tcl
#
# Output:
#   ip_repo/fdiv_axi_lite_1_0/component.xml

set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir .. 03_DIV_AXI]]
set project_dir [file join $script_dir vivado_fdiv_ip_pack]
set ip_repo_dir [file join $script_dir ip_repo]
set ip_root [file join $ip_repo_dir fdiv_axi_lite_1_0]
set part_name xck26-sfvc784-2LV-c

create_project FDIV_IP_PACK $project_dir -part $part_name -force

add_files -norecurse [list \
    [file join $rtl_dir fdiv_top.v] \
    [file join $rtl_dir fdiv_mant_divider.v] \
    [file join $rtl_dir fdiv_axi_lite.v] \
]

set_property top fdiv_axi_lite [get_filesets sources_1]
update_compile_order -fileset sources_1

ipx::package_project \
    -root_dir $ip_root \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -force

set core [ipx::current_core]
set_property name fdiv_axi_lite $core
set_property display_name {FDIV AXI4-Lite} $core
set_property description {IEEE 754 single-precision floating-point divider with AXI4-Lite register interface.} $core
set_property vendor_display_name {Student FDIV} $core
set_property version 1.0 $core

# Vivado usually infers these from the standard s_axi_* names. The catch
# blocks keep the script usable across Vivado versions that already inferred
# the interfaces during package_project.
catch {ipx::infer_bus_interface s_axi xilinx.com:interface:aximm_rtl:1.0 $core}
catch {ipx::infer_bus_interface s_axi_aclk xilinx.com:signal:clock_rtl:1.0 $core}
catch {ipx::infer_bus_interface s_axi_aresetn xilinx.com:signal:reset_rtl:1.0 $core}
catch {ipx::associate_bus_interfaces -busif s_axi -clock s_axi_aclk $core}

set axi_busif_name ""
foreach candidate {s_axi S_AXI} {
    if {[llength [ipx::get_bus_interfaces $candidate -of_objects $core -quiet]] != 0} {
        set axi_busif_name $candidate
    }
}

if {$axi_busif_name ne ""} {
    catch {ipx::associate_bus_interfaces -busif $axi_busif_name -clock s_axi_aclk $core}

    if {[llength [ipx::get_memory_maps $axi_busif_name -of_objects $core -quiet]] == 0} {
        ipx::add_memory_map $axi_busif_name $core
    }

    set_property slave_memory_map_ref $axi_busif_name [ipx::get_bus_interfaces $axi_busif_name -of_objects $core]

    if {[llength [ipx::get_address_blocks Reg -of_objects [ipx::get_memory_maps $axi_busif_name -of_objects $core] -quiet]] == 0} {
        ipx::add_address_block Reg [ipx::get_memory_maps $axi_busif_name -of_objects $core]
    }

    set reg_block [ipx::get_address_blocks Reg -of_objects [ipx::get_memory_maps $axi_busif_name -of_objects $core]]
    set_property range 4096 $reg_block
    set_property width 32 $reg_block
}

ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

puts "FDIV IP packaged at: $ip_root"
puts "Add this repository in Vivado: $ip_repo_dir"
