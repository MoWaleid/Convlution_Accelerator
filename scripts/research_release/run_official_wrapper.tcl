# Optional batch entry for the official profile-wrapper runner.
# The GUI console sets the two variables directly; batch mode passes them as
# argv. Both paths end in the runner's PROFILE_WRAPPER_PASS marker or an
# error (fail-closed).
#   vivado -mode batch -source run_official_wrapper.tcl -tclargs <RELEASE_ID> <VARIANT>
set script_dir [file normalize [file dirname [info script]]]
if {![info exists profile_wrapper_release]} {
    if {[info exists argv] && [llength $argv] >= 1} {
        set profile_wrapper_release [lindex $argv 0]
    } else {
        error "usage: vivado -mode batch -source run_official_wrapper.tcl -tclargs <RELEASE_ID> <VARIANT>"
    }
}
if {![info exists profile_wrapper_variant]} {
    if {[llength $argv] >= 2} {
        set profile_wrapper_variant [lindex $argv 1]
    } else {
        set profile_wrapper_variant optimized
    }
}
source [file join $script_dir test_profile_wrappers.tcl]
