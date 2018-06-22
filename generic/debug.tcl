#
# General purpose debugging functions for use in NSBD.  They are not used
#  during normal operation, although they are included in the program.
#
# Copyright (C) 1996-2003 by Dave Dykstra and Lucent Technologies
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#  
# If those terms are not sufficient for you, contact the author to 
# discuss the possibility of an alternate license.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# print out the contents of an array
# Dave Dykstra 08 Nov 1996

proc dumpArray {arrayname {fd stdout}} {
    upvar $arrayname array
    foreach k [array names array] {
	puts $fd "$k: $array($k)"
    }
}

#
# calculate the memory usage of a variable
# Dave Dykstra 21 May 1999
#
proc memusageVar {varname} {
    upvar $varname var
    if {![info exists var]} {
	return 0
    }
    if {[array exists var]} {
	set total 0
	foreach name [array names var] {
	    incr total [string length $name]
	    incr total [memusageVar var($name)]
	}
	return $total
    }
    return [string length $var]
}

#
# dump memory usage of all global variables over threshold, largest first
# Dave Dykstra 21 May 1999
#
proc dumpMemusage {{threshold 1000}} {
    set all ""
    foreach var [info globals] {
	global $var
	set usage [memusageVar $var]
	if {$usage >= $threshold} {
	    lappend all [list $usage $var]
	}
    }
    set total 0
    foreach pair [lsort -decreasing -integer -index 0 $all] {
	set amount [lindex $pair 0]
	incr total $amount
	puts "$amount: [lindex $pair 1]"
    }
    puts "$total bytes over threshold of $threshold"
}

# print the current stack with accessible variables at each level
# Dave Dykstra 30 Oct 1996, expanded from printStack in Ousterhoust's book

proc printStack {{fd "stdout"}} {
    set level [info level]
    for {set i 1} {$i < $level} {incr i} {
	puts $fd " Level $i: [info level $i]"
	foreach v [lsort [uplevel #$i info vars]] {
	    upvar #$i $v j
	    puts -nonewline $fd "  $v: "
	    if {[array exists j]} {
		puts $fd "(array)"
	    } elseif {[info exists j]} {
		puts $fd $j
	    } else {
		puts $fd "(doesn't exist)"
	    }
	}
    }
}

# display accesses to a variable
# Dave Dykstra 30 Oct 1996, expanded from example in Ousterhoust's book

proc printTracedVariable {name element op} {
    if {$element != ""} {
	set name ${name}($element)
    }
    upvar $name x
    switch "$op" {
	w {puts -nonewline "$name set to [list $x]"}
	r {puts -nonewline "$name read as [list $x]"}
	u {puts -nonewline "$name unset, trace removed"}
    }
    set lev [info level]
    if {$lev == 1} {
	puts " at top level"
    } else {
	puts " in [info level [incr lev -1]]"
    }
}

proc traceVar {varName {op wu}} {
    uplevel "trace variable $varName $op printTracedVariable"
    uplevel "trace vinfo $varName"
}

proc untraceVar {varName {op wu}} {
    uplevel "trace vdelete $varName $op printTracedVariable"
    uplevel "trace vinfo $varName"
}
