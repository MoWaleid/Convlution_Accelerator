# Complete branch-specific RTL suite.
set scripts [file dirname [file normalize [info script]]]
source [file join $scripts test_engine_regressions.tcl]
foreach variant {baseline optimized baseline_stress optimized_stress negative_control} {
    set argv [list $variant]
    source [file join $scripts test_edge_bubbles.tcl]
}
puts "EDGEFREE_RELEASE_RTL_PASS"

