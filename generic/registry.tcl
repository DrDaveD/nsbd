# Functions to handle the Nsbd Registry Database.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 20 Dec 1996
#
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

proc nrdInit {} {
    global nrdContentsCache nrdContentsCacheTime
    catch {unset nrdContentsCache}
    set nrdContentsCacheTime 0
    global nrdUpdatePackage nrdUpdates nrdNumChanges
    set nrdUpdatePackage ""
    set nrdUpdates ""
    set nrdNumChanges 0
}

#
# Lookup the keyword for the package in the registry database
#
proc nrdLookup {package keyword} {
    # nrdContents contains contents of any command-line .nrd files
    global nrdContents
    set key "packages $package $keyword"
    if {[info exists nrdContents($key)]} {
	# from a read-only .nrd file on the command line or from initFiles
	return $nrdContents($key)
    }

    global cfgContents nrdFileName
    global nrdContentsCache nrdContentsCacheTime nrdPackagesCache
    #
    # Only read the registry database file once during a run when
    #   looking things up.  I assume that writes by another NSBD program
    #   during a run can be ignored except when updating the database.
    #
    if {![info exists nrdContentsCache(packages)]} {
	if {[file exists $nrdFileName]} {
	    file stat $nrdFileName statb
	    set nrdContentsCacheTime $statb(mtime)
	    if {[file writable [file dirname $nrdFileName]]} {
		# lock out other writers while reading if possible
		lockFile $nrdFileName
		procfile $nrdFileName nrd nrdContentsCache
		unlockFile $nrdFileName
	    } else {
		procfile $nrdFileName nrd nrdContentsCache
	    }
	} elseif {![info exists nrdPackagesCache]} {
	    set nrdPackagesCache ""
	}
	if {![info exists nrdContentsCache(packages)]} {
	    set nrdContentsCache(packages) ""
	}
	alwaysEvalFor $nrdFileName {} {
	    foreach package $nrdContentsCache(packages) {
		validatePackageName $package
	    }
	}
    }

    if {[info exists nrdContentsCache($key)]} {
	return $nrdContentsCache($key)
    }

    return ""
}

#
# Return the entire list of packages
#

proc nrdPackages {} {
    global nrdContentsCache nrdPackagesCache
    if {![info exists nrdContentsCache(packages)]} {
	# for now, do a dummy nrdLookup to get it read in
	nrdLookup "" ""
    }
    return $nrdPackagesCache
}

#
# Return whether or not a package is registered
#

proc nrdPackageRegistered {package} {
    return [expr {[lsearch -exact [nrdPackages] $package] >= 0}]
}

#
# Queue an update to a package in the registry database.
# Update doesn't actually get written out until nrdCommitUpdates is called,
#   but further nrdLookups will find it.
# There are four parameters
#   1. The name of the package
#   2. operation, one of:
#       deletePackage - delete the entire package. 
#      	set - set the keyword to the value.  If value is empty string,
#		delete the keyword.
#	add - if keyword's value is a list, add all items in given value
#               to the list; if it is not a list, set the value.
#	delete - delete the given value(s) from the registered
#		keywords, if present
#   3. keyword
#   4. value
#

proc nrdUpdate {package operation keyword value} {
    global nrdUpdatePackage nrdUpdates
    if {($nrdUpdatePackage != $package) && ($nrdUpdatePackage != "")} {
	nsbderror "Internal error: must commit updates before changing packages"
    }
    if {[nrdApplyUpdate $package $operation $keyword $value]} {
	set nrdUpdatePackage $package
	lappend nrdUpdates [list $operation $keyword $value]
    }
}

#
# Apply the update to the nrdContentsCache
# Return the number of changes that this update effected
#
proc nrdApplyUpdate {package operation keyword value} {
    upvar #0 nrdContentsCache cache
    global nrdNumChanges nrdContents nrdPackagesCache
    # since it is expensive to write, keep track of number of changes
    set changes 0
    switch $operation {
	deletePackage {
	    set idx [lsearch -exact $cache(packages) $package]
	    if {$idx >= 0} {
		set cache(packages) [lreplace $cache(packages) $idx $idx]
		incr changes
	    } else {
		nsbderror "package $package was not registered, cannot delete"
	    }
	    if {![info exists nrdContents(packages)] || \
		    ([lsearch -exact nrdContents(packages) $package] < 0)} {
		# also remove it from the packages cache
		set idx [lsearch -exact $nrdPackagesCache $package]
		set nrdPackagesCache [lreplace $nrdPackagesCache $idx $idx]
	    }
	}
	set {
	    if {$value == ""} {
		# delete the entire value
		if {[info exists cache([list packages $package $keyword])]} {
		    unset cache([list packages $package $keyword])
		    incr changes
		}
	    } elseif {![info exists cache([list packages $package $keyword])] ||
		    ($cache([list packages $package $keyword]) != $value)} {
		set cache([list packages $package $keyword]) $value
		incr changes
	    }
	}
	add {
	    # for lists, add each value that's not already there
	    # for non lists, set the value
	    global nrdKeytable
	    if {$nrdKeytable([list packages $keyword])} {
		foreach val $value {
		    incr changes [luniqueAppend \
			cache([list packages $package $keyword]) $val]
		}
	    } elseif {![info exists cache([list packages $package $keyword])] ||
		    ($cache([list packages $package $keyword]) != $value)} {
		set cache([list packages $package $keyword]) $value
		incr changes
	    }
	}
	delete {
	    if {![info exists cache([list packages $package $keyword])]} {
		continue
	    }
	    # for lists, delete each value that's there
	    # for non lists, delete the value if that's what the
	    #  value is
	    global nrdKeytable
	    if {$nrdKeytable([list packages $keyword])} {
		foreach val $value {
		    if {[set idx [lsearch -exact \
		     $cache([list packages $package $keyword]) $val]] >= 0} {
			incr changes
			set new [lreplace \
			 $cache([list packages $package $keyword]) $idx $idx]
			if {$new == ""} {
			    unset cache([list packages $package $keyword]) 
			    break
			} else {
			    set cache([list packages $package $keyword]) $new
			}
		    }
		}
	    } elseif {$cache([list packages $package $keyword]) == $value} {
		unset cache([list packages $package $keyword])
		incr changes
	    }
	}
	default {
	    nsbderror "Internal error: invalid nrdUpdate operation: $operation"
	}
    }
    if {$changes > 0} {
	if {$operation != "deletePackage"} {
	    # add package if it doesn't exist yet
	    if {[luniqueInsert cache(packages) $package]} {
		incr changes
		luniqueInsert nrdPackagesCache $package
	    }
	}
	incr nrdNumChanges $changes
    }
    return $changes
}

#
# Write all committed updates to the database
#
proc nrdCommitUpdates {} {
    global nrdUpdatePackage nrdUpdates nrdNumChanges
    if {$nrdNumChanges == 0} {
	# nothing to do
	return ""
    }
    global cfgContents nrdContentsCache nrdContentsCacheTime nrdFileName
    lockFile $nrdFileName
    if {[file exists $nrdFileName]} {
	file stat $nrdFileName statb
	if {$statb(mtime) > $nrdContentsCacheTime} {
	    # Old file has changed since we last checked
	    # Re-read it, and re-apply updates
	    catch {unset nrdContentsCache}
	    procfile $nrdFileName nrd nrdContentsCache
	    set nrdContentsCacheTime $statb(mtime)
	    set nrdNumChanges 0
	    foreach opKeyVal $nrdUpdates {
		eval nrdApplyUpdate $nrdUpdatePackage $opKeyVal
	    }
	}
    }
    progressmsg "Updating $nrdFileName"
    set newRegName [addFilePrefix $nrdFileName new]
    file delete -force $newRegName
    if {[info exists nrdContentsCache(regenerateComments)]} {
	withOpen fd $newRegName "w" {
	    nsbdGenTemplate $fd nrd nrdContentsCache
	}
    } else {
	nsbdGenFile $newRegName nrd nrdContentsCache \
"# Last regenerated by NSBD at [currentTime]
\# To put in keyword comments until the next update, use
\#     nsbd -updateComments $nrdFileName
\# To regenerate comments every time, set regenerateComments: key to anything"
    }
    if {[file exists $nrdFileName]} {
	file rename -force $nrdFileName [addFilePrefix $nrdFileName old]
    }
    file rename $newRegName $nrdFileName
    file stat $nrdFileName statb
    set nrdContentsCacheTime $statb(mtime)
    unlockFile $nrdFileName
    set nrdUpdatePackage ""
    set nrdUpdates ""
    set nrdNumChanges 0
}

#
# Abort cached database changes
#
proc nrdAbortUpdates {} {
    global nrdNumChanges
    if {$nrdNumChanges != 0} {
	nrdInit
    }
}

