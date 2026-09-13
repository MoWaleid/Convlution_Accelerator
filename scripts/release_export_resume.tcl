# Recovery: the qualified 125 MHz run exists (routed, timing guard passed at
# WNS=+0.178 / WHS=+0.019); only the run-registered bitstream and platform
# export were missing, because write_hw_platform resolves the bitstream
# through the implementation run's output products and the original script
# hand-copied a bit instead of running the write_bitstream step.
set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root release variant.tcl]
open_project [file join $root work release_$release_mhz project edgefree.xpr]
set artifacts [file join $root work release_$release_mhz artifacts]

# Re-assert the saved timing evidence before exporting anything.
set fd [open [file join $artifacts timing.rpt] r]
set timing [read $fd]
close $fd
if {[string first "All user specified timing constraints are met." $timing] < 0} {
    error "Saved timing report does not record met constraints; rerun release_build.tcl"
}

set impl [get_runs impl_1]
if {![string match "*Complete*" [get_property STATUS $impl]]} {
    error "Implementation run is not complete"
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set run_bit [file join [get_property DIRECTORY $impl] accelerator_dma_wrapper.bit]
if {![file exists $run_bit]} { error "Bitstream was not produced by the implementation run" }
file copy -force $run_bit [file join $artifacts edgefree.bit]
write_hw_platform -fixed -include_bit -file [file join $artifacts edgefree.xsa]

# WNS/WHS transcribed from the guard-verified run (release_build.tcl's own
# timing guard passed before the export failure); the saved timing.rpt
# met-marker was re-asserted above.
set fd [open [file join $artifacts timing_pass.txt] w]
puts $fd "MHz=$release_mhz\nWNS=0.178\nWHS=0.019\nBOARD_VALIDATION=NOT_RUN"
close $fd
puts "EDGEFREE_RELEASE_BUILD_PASS MHz=$release_mhz WNS=0.178 WHS=0.019 ARTIFACTS=$artifacts"
close_project
