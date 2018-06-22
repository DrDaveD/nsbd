#
# Tcl-equivalent functions of NSBD C functions, for use when
#   run directly by tclsh via "evalnsbd".
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 13 Dec 1996
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

#
# start the Tk toolkit
#
proc startTk {} {
    package require Tk
}

#
# make a symbolic link without expanding anything
#
proc primitiveSymLink {fromFile toFile} {
    exec ln -s $fromFile $toFile
}

#
# make a hard link without expanding anything
#
proc primitiveHardLink {fromFile toFile} {
    exec ln $fromFile $toFile
}

#
# do chmod without expanding anything
#
proc primitiveChangeMode {path mode} {
    exec chmod $mode $path
}

#
# get a group id number from a name
#
proc getGroupIdFromName {name} {
    return [exec sed -n "/^$name:/{s/^$name\:\:\\(\[^:\]*\\):.*/\\1/p;q;}" /etc/group]
}

#
#
#
proc getGroupNameFromId {gid} {
    return [exec sed -n "/^\[^:\]*\:\:$gid:/{s/^\\(\[^:\]*\\)::$gid:.*/\\1/p;q;}" /etc/group]
}

#
# do chgrp without expanding anything
#
proc primitiveChangeGroup {path group} {
    exec chgrp $group $path
}

#
# do touch, converting the unix time to YYYYMMDDHHSS format
#
proc primitiveChangeMtime {path mtime} {
    exec touch -t [clock format $mtime -format "%Y%m%d%H%M.%S"] $path
}

#
# set the umask
#
proc umask {mask} {
    # can't be done in native tcl, ignore it
    debugmsg "skipping setting umask"
}

#
# return whether or not stdin is a tty
#
proc stdinisatty {} {
    if {[catch {exec tty -s} result] == 0} {
	return 1
    }
    return 0
}

#
# initialize nsbdnestlevel variables
#

proc nsbdnestlevelInit {} {
    upvar #0 nsbdnestlevel_level nestlevel
    upvar #0 nsbdnestlevel_length nestlength
    set nestlevel 0
    catch {unset nestlength}
    set nestlength(0) 0
}

# nsbdnestlevel figures out the nestlevel in a line of an "nsbd" file.
# parameters are
#    1. line - the line to parse
#    2. linelength - the number of bytes in the line
#    3. lineno - the line number that is being parsed
# returns list of two items: the nesting level and the number of characters
#    of whitespace at the beginning of the line
# this is a good candidate for writing in C for speed
# 

proc nsbdnestlevel {line linelength lineno} {
    upvar #0 nsbdnestlevel_level nestlevel
    upvar #0 nsbdnestlevel_length nestlength
    # nlength is nestlength for this line
    set nlength 0
    # whitechars is number of characters of whitespace (tab counts as 1)
    set whitechars 0
    set chr ""
    for {set idx 0} {$idx < $linelength} {incr idx} {
	set chr [string index $line $idx]
	if {$chr == " "} {
	    incr nlength
	    incr whitechars
	} elseif {$chr == "\t"} {
	    incr nlength [expr {8 - ($nlength % 8)}]
	    incr whitechars
	} else {
	    break
	}
    }
    if {($chr == "#") || ($whitechars == $linelength)} {
	# ignore comments and blank lines
	return "$nestlevel $whitechars"
    }
    set curlength $nestlength($nestlevel)
    if {$nlength != $curlength} {
	if {$nlength > $curlength} {
	    incr nestlevel
	    set nestlength($nestlevel) $nlength
	} else {
	    # must be less, find out which if any previous nest level matches
	    unset nestlength($nestlevel)
	    incr nestlevel -1
	    while {($nestlevel > 0) && ($nlength < $nestlength($nestlevel))} {
		unset nestlength($nestlevel)
		incr nestlevel -1
	    }
	    if {$nlength != $nestlength($nestlevel)} {
		nsbderror "invalid indent level on line $lineno"
	    }
	}
    }
    return "$nestlevel $whitechars"
}

#
# Return a boolean indicating whether two glob patterns overlap
# Do a string match on each path component (separated by "/") separately,
#   and if the last component in one of the patterns is "*" let it match
#   the rest of the other pattern
#
proc matchpatterns {pat1 pat2} {
    set regwildcards {(\[)|(\])|([*?])}
    if {![regexp $regwildcards $pat1] && ![regexp $regwildcards $pat2]} {
	# no wildcards
	return [expr {$pat1 == $pat2}]
    }
    set lpat1 [split $pat1 "/"]
    set lpat2 [split $pat2 "/"]
    set len1 [llength $lpat1]
    set len2 [llength $lpat2]
    set idx 0
    foreach comp1 $lpat1 {
       	set comp2 [lindex $lpat2 $idx]
	incr idx
	if {$idx > $len2} {
	    return 0
	}
	if {$comp1 == "*"} {
	    if {$idx == $len1} {
		return 1
	    }
	    if {$comp2 != "*"} {
		continue
	    }
	    # fall through to the check for the end of comp2
	}
	if {$comp2 == "*"} {
	    if {$idx == $len2} {
		return 1
	    }
	    continue
	}
	if {$comp1 == $comp2} {
	    continue
	}
	if {[string match $comp1 $comp2] || [string match $comp2 $comp1]} {
	    continue
	}
	return 0
    }
    return [expr {$len1 == $len2}]
}

