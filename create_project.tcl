# =====================================================================
#  create_project.tcl  -  re-creates the Vivado project from the repo
#  Usage (in Vivado):  Tools > Run Tcl Script... > create_project.tcl
#     or terminal:     vivado -mode batch -source create_project.tcl
#  The project is created in the folder  vivado/  (ignored by Git).
# =====================================================================
set root [file dirname [file normalize [info script]]]

create_project risc8_5stage $root/vivado -part xc7a35tcpg236-1 -force

# Design sources + program memory
add_files -fileset sources_1 [glob $root/rtl/*.v]
add_files -fileset sources_1 $root/program.hex
set_property file_type {Memory File} [get_files program.hex]
set_property top risc8_5stage_core [get_filesets sources_1]

# Simulation sources
add_files -fileset sim_1 $root/tb/tb_risc8_5stage.v
set wcfg $root/tb/tb_risc8_5stage_behav.wcfg
if {[file exists $wcfg]} { add_files -fileset sim_1 $wcfg }
set_property top tb_risc8_5stage [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Project created: $root/vivado/risc8_5stage.xpr"
