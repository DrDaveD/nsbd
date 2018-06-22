#
# Functions to process '.nsb' files, to generate them and act upon them.
# Generating them involves reading the '.npd' files into the "npdContents"
#   associative array and using that to generate the contents of the '.nsb'
#   files into the "nsbContents" array and from there write them out.
# Acting upon them involves reading them back from the file into "nsbContents",
#   creating a temporary internal array "nupContents" which is similar but has
#   substitutions applied and unchanged files removed (relative to the
#   previously installed package), fetching the changed files over the 
#   network into a temporary directory, and installing the files from the
#   temporary directory into their final location.  The "nupContents" array
#   is also written out and passed to pre/postUpdateCommands.
# This source file also contains the GUI (tk) code for registering new
#   packages, intended for use from a web browser.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 22 Nov 1996
#
#
# Copyright (C) 1997-2003 by Dave Dykstra and Lucent Technologies
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

# ------------------------------------------------------------------
# functions used to create '.nsb' files
# ------------------------------------------------------------------

#
# make a '.nsb' contents table, starting from the package description
#   contents table which came from an '.npd' file
#

proc makeNsbContents {npdContentsName nsbContentsName} {
    upvar $npdContentsName npdContents
    upvar $nsbContentsName nsbContents
    catch {unset nsbContents}

    validatePackageName $npdContents(package)

    global npdNsbKeys cfgContents
    applyKeys $npdNsbKeys npdContents nsbContents nsb

    global knownMdTypes
    if {[info exists cfgContents(mdType)]} {
	set mdType $cfgContents(mdType)
	if {[lsearch -exact $knownMdTypes $mdType] < 0} {
	    nsbderror "unknown mdType: $mdType; should be one of $knownMdTypes"
	}
    } else {
	set mdType [lindex $knownMdTypes 0]
    }

    set nsbContents(generatedBy) [nsbdVersion]
    set nsbContents(generatedAt) [currentTime]


    if {[info exists npdContents(localTop)]} {
	set localTop $npdContents(localTop)
    } else {
	set localTop "."
    }
    if {![file isdirectory $localTop]} {
	nsbderror "localTop is not an existing directory: $localTop"
    }

    # this will canonicalize the directory name, with one slash at the end
    set globTop [glob $localTop]
    if {[llength $globTop] > 1} {
	nsbderror "localTop may not contain wildcards or spaces: $localTop"
    }
    if {$globTop == "/"} {
	set localTop "/"
    } else {
	set localTop $globTop/
    }
    set relStart [string length $localTop]

    if {![info exists npdContents(paths)]} {
	warnmsg "Warning: no 'paths' keyword found"
	return
    }
    if {[info exists npdContents(topUrl)] ||
		[info exists npdContents(multigetUrl)]} {
	if {![info exists npdContents(nsbUrl)]} {
	    warnmsg "Warning: no 'nsbUrl' keyword although there is 'topUrl' or 'multigetUrl'"
	}
    } else {
	if {[info exists npdContents(nsbUrl)]} {
	    warnmsg "Warning: no 'topUrl' or 'multigetUrl' keyword although there is 'nsbUrl'"
	}
    }

    if {[info exists npdContents(pathModes)]} {
	# expand %V and %E in each pathMode, if any
	set pathModes ""
	foreach pathMode $npdContents(pathModes) {
	    if {[regexp %V $pathMode]} {
		if {[info exists npdContents(version)]} {
		    regsub -all %V $pathMode $npdContents(version) pathMode
		} else {
		    regsub -all %V $pathMode "" pathMode
		}
	    }
	    if {[regexp %E $pathMode]} {
		if {[info exists npdContents(executableTypes)]} {
		    # %E expands to a pathMode for each executableType
		    foreach executableType $npdContents(executableTypes) {
			regsub -all %E $pathMode $executableType result
			lappend pathModes $result
		    }
		} else {
		    regsub -all %E $pathMode "" pathMode
		    lappend pathModes $pathMode
		}
	    } else {
		lappend pathModes $pathMode
	    }
	}
	set npdContents(pathModes) $pathModes
    }

    if {[info exists npdContents(executableTypes)] && \
	    [info exists cfgContents(executableTypes)]} {
	# calculate values for %X from config file settings so don't have
	#   to do it for every path
	foreach type $npdContents(executableTypes) {
	    # the following is a temporary internal keyword
	    set npdContents([list executableTypes $type extension]) \
					    [getExecutableTypeExtension $type]
	}
    }

    set numerrors 0
    foreach path $npdContents(paths) {
	if {[set msg [relativePathCheck $path]] != ""} {
	    nsbpatherror $msg
	    continue
	}

	#
	# Expand %V
	#
	if {[regexp %V $path]} {
	    if {[info exists npdContents(version)]} {
		regsub -all %V $path "$npdContents(version)" path
	    } else {
		regsub -all %V $path "" path
	    }
	}
	#
	# Expand %E into each executableType
	#
	set globbedPaths 0
	if {[regexp %E $path]} {
	    if {[info exists npdContents(executableTypes)]} {
		set paths ""
		set globbedPaths 1
		foreach type $npdContents(executableTypes) {
		    regsub -all %E $path $type subpath
		    set ext ""
		    set extkey [list executableTypes $type extension]
		    if {[info exists npdContents($extkey)]} {
			set ext $npdContents($extkey)
		    }
		    regsub -all %X $subpath $ext subpath
		    if {[pathExcluded $subpath]} {
			continue
		    }
		    set globPaths [robustGlob "$localTop$subpath"]
		    if {$globPaths == ""} {
			nsbpatherror "path not found: $localTop$subpath"
		    }
		    foreach exppath $globPaths {
			lappend paths $exppath
		    }
		}
	    } else {
		nsbpatherror "no executableTypes known for %E in path $path"
	    }
	} elseif {[regexp %X $path]} {
	    nsbpatherror "%X not used with %E in path $path"
	}
	if {!$globbedPaths} {
	    if {[pathExcluded $path]} {
		continue
	    }
	    set paths [robustGlob "$localTop$path"]
	    if {$paths == ""} {
		nsbpatherror "path not found: $localTop$path"
	    }
	}
	foreach exppath $paths {
	    nsbexpandpath $mdType $exppath $relStart npdContents nsbContents
	}
    }
    if {$numerrors > 0} {
	if {$numerrors == 1} {
	    set msg "there was 1 path error"
	} else {
	    set msg "there were $numerrors path errors"
	}
	if {![stdinisatty]} {
	    nsbderror $msg
	}
	puts stderr "Warning: $msg"
	puts -nonewline stderr \
		{Do you want to proceed without those paths? [no] }
	flush stderr
	set ans [gets stdin]
	if {![string match {*[yY]*} $ans]} {
	    nsbderror $msg
	}
    }
}

#
# keep a count of the number of errors, print message, and continue
#   so all errors can be located in one pass
#
proc nsbpatherror {str} {
    upvar numerrors numerrors
    warnmsg $str
    incr numerrors
}

#
# Return true if path is excluded by the excludePaths keyword or 
#   -cvsExclude option
#
proc pathExcluded {path} {
    upvar npdContents npdContents

    if {[info exists npdContents(excludePaths)]} {
	foreach excludePath $npdContents(excludePaths) {
	    if {[string match $excludePath $path]} {
		debugmsg "$path excluded by excludePath $excludePath"
		return 1
	    }
	}
    }
    global cvsExclude cvsExcludePats
    if {[info exists cvsExclude]} {
	foreach pattern $cvsExcludePats {
	    if {[string match $pattern $path]} {
		debugmsg "$path excluded by CVS pattern $pattern"
		return 2
	    }
	}
    }
    return 0
}

#
# Return true if mtime is to be preserved due to the pathPreserveMtimes keyword
#
proc pathMtimePreserved {path} {
    upvar npdContents npdContents

    if {[info exists npdContents(pathPreserveMtimes)]} {
	foreach preservePath $npdContents(pathPreserveMtimes) {
	    if {[string match $preservePath $path]} {
		debugmsg "mtime preserved for $path due to pathPreserveMtimes pattern $preservePath"
		return 1
	    }
	}
    }
    return 0
}

#
# expand the path into the nsbContents.  relStart is the string index
#  of the relative portion of the path.
#
proc nsbexpandpath {mdType path relStart npdContentsName nsbContentsName} {
    upvar numerrors numerrors
    upvar pathTable pathTable
    upvar hardLinkTable hardLinkTable
    upvar $npdContentsName npdContents
    upvar $nsbContentsName nsbContents
    global cvsExclude

    set relPath [string range $path $relStart end]

    if {[pathExcluded $relPath]} {
	return
    }

    if {[catch {file readlink $path} link] == 0} {
	# symbolic link.  If the link is to another path that *could be* in
	#   the package (i.e., under the same relative base) and it is a
	#   relative path itself, include it as a linkTo.  Perhaps the user
	#   would prefer to only have it remembered as a linkTo if the path
	#   *is* in the package, but that's much harder to implement.
	if {[string index $link 0] != "/"} {
	    set link [cleanPath [file join [file dirname $relPath] $link]]
	    # if remaining link does not begin with ../, it is below
	    #   the base so remember it as a 'linkTo'
	    if {[string range $link 0 2] != "../"} {
		if {![nsbaddpath $relPath nsbContents]} return
		lappend nsbContents([list paths $relPath linkTo]) $link
		return
	    }
	}
	# notify user when not making it a linkTo as that is often done
	#  by mistake
	progressmsg "Note: following the symlink at\n    [cleanPath $path]\n  because it points outside of top directory (eliminate message with verbose=3)"
    }
    if {[file isdirectory $path]} {
	if {[info exists npdContents(excludePaths)]} {
	    # look also for excludePaths that end in "/"
	    foreach excludePath $npdContents(excludePaths) {
		if {[string match $excludePath $relPath/]} {
		    return
		}
	    }
	}

	debugmsg "Including all files in directory $relPath"

	addCvsIgnore $path $path

	if {![nsbaddpath $relPath/ nsbContents]} return

	# Escape any {} character, as they are special to tcl.  Don't
	# do it more than once, though.
	regsub -all {([^\\])(\{|\})} $path {\1\\\2} path

	foreach exppath [glob $path/{.?*,*}] {
	    if {[file tail $exppath] != ".."} {
		nsbexpandpath $mdType $exppath $relStart npdContents nsbContents
	    }
	}
    } else {
	debugmsg "Including $relPath"
	set code [catch {file stat $path statb} string]
	if {$code != 0} {
	    nsbpatherror "$string"
	    return
	}
	if {[info exists statb(nlink)] && ($statb(nlink) > 1) &&
	    [info exists statb(dev)] && [info exists statb(ino)]} {
	    # the file has a hard link
	    set key "$statb(dev).$statb(ino)"
	    if {![info exists hardLinkTable($key)]} {
		# first time we've seen this file
		set hardLinkTable($key) $relPath
	    } else {
		# second or later time we've seen this file
		if {![nsbaddpath $relPath nsbContents]} return
		lappend nsbContents([list paths $relPath hardLinkTo]) \
			$hardLinkTable($key)
		return
	    }
	}
	set code [catch {set fd [open $path "r"]} string]
	if {$code != 0} {
	    nsbpatherror "$string"
	    return
	}
	fconfigure $fd -translation binary
	set code [catch {set mdList [$mdType -chan $fd]} string]
	close $fd
	if {$code != 0} {
	    nsbpatherror "error during $mdType of $path: $string"
	    return
	}

	if {![nsbaddpath $relPath nsbContents]} return
	set nsbContents([list paths $relPath length]) [lindex $mdList 0]
	set nsbContents([list paths $relPath $mdType]) [lindex $mdList 1]

	set mode ""
	if {[info exists npdContents(pathModes)]} {
	    foreach pathMode $npdContents(pathModes) {
		set val ""
		regexp "^(\[^ \t\]*)\[ \t\]*(.*)" $pathMode x pattern val
		if {[string match $pattern $relPath]} {
		    foreach letter {r w x} {
			if {[string first $letter $val] >= 0} {
			    append mode $letter
			}
		    }
		    break
		}
	    }
	}
	if {$mode == ""} {
	    set mode "r"
	    if {[file writable $path]} {
		set mode "${mode}w"
	    }
	    if {[file executable $path]} {
		set mode "${mode}x"
	    }
	}
	if {$mode != "rw"} {
	    set nsbContents([list paths $relPath mode]) $mode
	}

	if {[pathMtimePreserved $relPath]} {
	    set nsbContents([list paths $relPath mtime]) $statb(mtime)
	}
    }
}

#
# add a path to nsbContents(paths), if it was not already there
# return 1 if successful, otherwise 0
#
proc nsbaddpath {path nsbContentsName} {
    upvar $nsbContentsName nsbContents
    upvar pathTable pathTable
    upvar numerrors numerrors
    if {[info exists pathTable($path)]} {
	nsbpatherror "duplicate path $path"
	return 0
    }
    set pathTable($path) ""
    lappend nsbContents(paths) $path
    return 1
}

# ------------------------------------------------------------------
# functions used when both creating and reading '.nsb' files
# ------------------------------------------------------------------

#
# check to make sure path is a relative path.
# If it is, return an empty string, otherwise return an error message
#
proc relativePathCheck {path} {
    set firstc [string index $path 0]
    if {$firstc == "/"} {
	return "path may not begin with slash: $path"
    }
    if {$firstc == "~"} {
	return "path may not begin with tilde: $path"
    }
    if {(($firstc == ".") && ([string index $path 1] == ".")) ||
		[regexp {/\.\./} "/$path/"]} {
	return ".. components not allowed in path: $path"
    }
    if {[regexp {{.*}} $path]} {
	# curly brackets would have an effect on glob which could defeat
	#  above checks; don't want to support them anyway because it
	#  would make reimplementation in a language other than tcl more
	#  difficult

# We've seen a need to support this, so disable check for now
#	return "curly brackets not allowed in path: $path"

   }
    return ""
}

#
# Clean up the path: remove multiple slashes, and as many "." and ".."
#   components in the path as possible, without changing the file referenced. 
# Note: paths starting with /.. do not get collapsed to / like they would on
#   unix, and a trailing slash does not get removed.
#
proc cleanPath {path} {
    while {[regsub "//" $path "/" path]} {}
    set path "/$path/"
    regsub -all {/\./} $path "/" path
    while {[regsub {/[^/][^/]*/\.\./} $path "/" path]} {}
    set path [string range $path 1 [expr [string length $path] - 2]]
    if {$path == ""} {
	return "."
    }
    return $path
}

#
# validate a package name value
#

proc validatePackageName {name} {
    # If you change the list here, also change the error message here and
    #   change the comments on the 'package' keys in tables.tcl.
    # Note: the dash in the regexp must be last to keep it from thinking it
    #   is a range
    if {![regexp {^[A-Za-z0-9!_.+-]+$} $name]} {
	nsbderror "package name must contain only alphanumeric or \[!_.+-\]: $name"
    }
}

# ------------------------------------------------------------------
# functions used when when reading '.nsb' files
# ------------------------------------------------------------------

#
# Process a '.nsb' Not-So-Bad file
#
proc procnsbfile {fd lineno filename expectedPackageName hassig nsbScratch} {
    global procNsbType noNsbChanges

    set noNsbChanges 0
    set package $expectedPackageName
    set distributedPackageName [nrdLookup $package distributedPackageName]
    if {$distributedPackageName == ""} {
	set distributedPackageName $package
    }

    global nsbContents
    catch {unset nsbContents}
    if {$procNsbType == "fetchAll"} {
	# process any contents
	nsbdParseContents $fd nsb $lineno $filename nsbContents
	if {![info exists nsbContents(package)]} {
	    nsbderror "no package keyword in file"
	}
	# fall through

    } elseif {$package == ""} {
	# process any contents, don't yet know the package name
	nsbdParseContents $fd nsb $lineno $filename nsbContents

	if {![info exists nsbContents(package)]} {
	    nsbderror "no package keyword in file"
	}

    } else {
	# only this package is allowed.
	if {($procNsbType != "audit-update") && \
		[set nsbStoreFiles [findNsbStoreFiles $package]] != ""} {
	    # See if it is exactly the same as an old one
	    foreach nsbStoreFile $nsbStoreFiles {
		set catchcode [catch {compareFiles $nsbScratch \
						$nsbStoreFile} answer]
		if {($catchcode == 0) && $answer} {
		    progressmsg "No change in .nsb file for package $package"
		    set noNsbChanges 1
		    # Go straight to post-processing, but parse the file
		    #  anyway for things like version and updateParameters
		    nsbdParseContents $fd nsb $lineno $filename nsbContents
		    bypassProcNsb $package nsbContents $nsbScratch
		    return
		}
		if {$catchcode > 0} {
		    debugmsg "could not compare to saved .nsb because $answer"
		}
	    }
	}

	global ignoreSecurity
	set matchid ""
	if {!$ignoreSecurity} {
	    # Make sure it has a valid signature for this package before trying
	    #  to parse it
	    if {!$hassig} {
		nsbderror "no PGP signature found; -ignoreSecurity required to process"
	    }
	    set maintainers [nrdLookup $package maintainers]
	    if {$maintainers == ""} {
		nsbderror "no authorized maintainers registered for package $package;\n  -ignoreSecurity required to process"
	    }
	    # check the PGP signature
	    set ans [pgpCheckFile $nsbScratch $filename]
	    foreach {variant goodsig ids warning} $ans {}
	    if {[llength $ids] == 1} {
		set idname "ID"
		set idlist "\"[lindex $ids 0]\""
		regsub {^"0x} $idlist {"Key ID 0x} idlist
	    } else {
		set idname "IDs"
		set idlist "\n  [join $ids "\n  "]"
		regsub "\n  0x" $idlist "\n  Key ID 0x" idlist
	    }
	    if {$goodsig} {
		foreach id $ids {
		    if {[lsearch -exact $maintainers $id] >= 0} {
			set matchid $id
			break
		    }
		}
		if {$matchid == ""} {
		    nsbderror "$idname not in authorized maintainers for package $package: $idlist"
		}
		updatemsg "Good signature from $idlist"
		if {$warning != ""} {
		    warnmsg "Warning from $variant for $filename:\nWARNING: $warning\n"
		}
	    } else {
		# !goodsig
		if {$warning != ""} {
		    set warning "\n$warning"
		}
		if {$ids == "*UNKNOWN*"} {
		    nsbderror "unrecognized key error from $variant$warning"
		}
		if {$ids != ""} {
		    nsbderror "bad signature from $variant $idname $idlist$warning"
		}
		nsbderror "error from $variant$warning"
	    }
	} elseif {$hassig} {
	    progressmsg "Ignoring signature because of -ignoreSecurity"
	}

	# any signature at the end of the file will be
	#   ignored by nsbdParseContents
	nsbdParseContents $fd nsb $lineno $filename nsbContents

	if {![info exists nsbContents(package)]} {
	    nsbderror "no package keyword in file"
	}

	if {$nsbContents(package) != $distributedPackageName} {
	    nsbderror "incorrect package: $nsbContents(package); expected $distributedPackageName"
	}

	set nsbContents(package) $package

	if {!$ignoreSecurity} {
	    set nsbContents(maintainers) [list $matchid]
	}
	if {[info exists nsbContents(releaseNote)]} {
	    noticemsg "$package releaseNote:\n  [join $nsbContents(releaseNote) "\n  "]"
	}
    }

    #
    # Apply command line keyword settings
    #
    applyCmdkeys nsbContents nsb


    #
    # Put out informational progress message
    #
    set package $nsbContents(package)
    validatePackageName $package
    if {![info exists nsbContents(generatedBy)]} {
	nsbderror "missing generatedBy field"
    }
    if {![info exists nsbContents(generatedAt)]} {
	nsbderror "missing generatedAt field"
    }
    updatemsg "$package '.nsb' file generated at $nsbContents(generatedAt)"
    updatemsg "  by $nsbContents(generatedBy)"


    #
    # Determine the applicable executableTypes and versions
    #
    set executableTypes [getExecutableTypes $package nsbContents]
    set versions [getVersions "" nsbContents]

    if {$procNsbType == "fetchAll"} {
	progressmsg "Fetching all files for verification"
	fetchAllNsbContents $executableTypes $versions $nsbScratch
	progressmsg "All URLs in $filename OK"
	return
    }

    checkOSVersions $executableTypes

    if {$procNsbType == "register"} {
	if {[promptUnmetRequirements $package $executableTypes]} {
	    promptToRegister $package $executableTypes $versions
	}
	return
    }

    #
    # check required packages
    #
    set unmet [unmetRequirementPackages $executableTypes]
    if {$unmet != ""} {
	set msglist ""
	foreach {pack msg nsbUrls} $unmet {
	    lappend msglist "Warning: required package $pack $msg"
	}
	warnmsg [join $msglist "\n"]
    }

    #
    # Continue in another routine, to avoid strings that are too long
    #   for tcl2c and to allow an entry point for bypassProcNsb
    #
    procnsbfile2 $package $executableTypes $versions $nsbScratch
}

#
# Bypass initial processing of nsbContents, but do post processing.
# Assume package has already been confirmed to be registered.
#

proc bypassProcNsb {package {nsbContentsName ""} {nsbScratch ""}} {
    if {$nsbContentsName == ""} {
	global nsbContents
	catch {unset nsbContents}
    } else {
	upvar $nsbContentsName nsbContents
    }

    set nsbContents(package) $package

    applyCmdkeys nsbContents nsb

    set executableTypes [getExecutableTypes $package nsbContents 1]
    set versions [getVersions $package nsbContents]

    procnsbfile2 $package $executableTypes $versions $nsbScratch
}

#
# Continue processing an nsbfile
# Does the main driving of the processing steps, calling these major functions:
#    1. makeNupContents -- creates internal "nupContents" array from the
#          "nsbContents" which is what's read in from the '.nsb' files
#    2. findConflictingNupPaths -- looks for other packages that have 
#          the same paths as the package of interest to handle cases when
#          files are moved from one package to another and to prevent
#          accidental overlaps between packages
#    3. getNupPathsInfo -- creates a list of paths of changed files to
#          retrieve along with a lot of related information for each file
#    4. multiFetchPaths or urlMultiMdCopy -- pulls the changed files into
#          the temporary directory
#    5. copyPortableTemps -- copies portable files if any from another 
#	   installTop if any, so they only need to be transferred over
#	   the network once
#    6. installNupPaths -- moves changed files from temporary directory
#	   to final install directory
#    7. stores the new .nsb files into their final location
#
proc procnsbfile2 {package executableTypes versions nsbScratch} {
    global nsbContents procNsbType noNsbChanges

    #
    # If the package will be stored in multiple places because of multiple
    #   executableTypes, process separately for each place.   Note that if
    #   an executableType is removed from the package, files that had
    #   been installed for that old executableType will be left alone
    #

    #
    # As a side effect this function sets four arrays: topNsbStoreNames and
    #   topRelocParams are indexed by the installTops, and storeExecutableTypes
    #   and storeVersions are indexed by the topNsbStoreNames
    #
    set installTops [calculateInstallTops $package $executableTypes $versions]

    #
    # Process the '.nsb' file separately for each installTop
    # First calculate which files are needed
    #
    set pathsInfo ""
    set nupCount 0
    set batchFetches 1
    if {($procNsbType != "changedPaths") && ($procNsbType != "batchUpdate")} {
	# If there are % substitutions in topUrl or multigetUrl, do fetches
	#  separately per installTop because multifetches require a single top
	foreach key {topUrl multigetUrl} {
	    if {[info exists nsbContents($key)]} {
		if {[regexp {%[EVP]} $nsbContents($key)]} {
		    set batchFetches 0
		    break
		}
	    }
	}
    }

    foreach top $installTops {
	incr nupCount
	upvar 0 nupContents_$nupCount nupContents
	upvar 0 hadPaths_$nupCount hadPaths

	#
	# if there are multiple topNsbStoreNames, pick the last because the
	#  reason for having more than one would be multiple versions, and
	#  the last installed is most likely the latest version
	#
	set nsbStoreName [lindex $topNsbStoreNames($top) \
			    [expr {[llength $topNsbStoreNames($top)] - 1}]]
	set etypes $storeExecutableTypes($nsbStoreName)
	set verss $storeVersions($nsbStoreName)
	if {$etypes == [list ""]} {
	    set etypes ""
	}
	if {$verss == [list ""]} {
	    set verss ""
	}

	set hadPaths [makeNupContents $nsbStoreName $nsbScratch $top \
						    $etypes $verss]
	findConflictingNupPaths $etypes

	if {$procNsbType == "preview"} {
	    if {!$noNsbChanges} {
		previewNupPaths
	    }
	} else {
	    getNupPathsInfo $nupCount pathsInfo $etypes $verss $topRelocParams($top)
	    if {!$batchFetches} {
		multiFetchPaths nupContents $pathsInfo $etypes $verss
		set pathsInfo ""
	    }
	}
    }

    if {$procNsbType == "preview"} {
	return
    }

    if {$procNsbType == "changedPaths"} {
	puts "-----BEGIN CHANGED PATHS-----"
	foreach pathInfo $pathsInfo {
	    puts [lindex $pathInfo 0]
	}
	puts "-----END CHANGED PATHS-----"
	return
    }

    #
    # Load all paths into temporary directories together
    #
    if {$procNsbType == "batchUpdate"} {
	global env
	if {[info exists env(CONTENT_LENGTH)] && ($env(CONTENT_LENGTH) != "")} {
	    urlMultiMdCopy "" $nupContents_1(mdType) $pathsInfo stdin \
							$env(CONTENT_LENGTH)
	} else {
	    urlMultiMdCopy "" $nupContents_1(mdType) $pathsInfo stdin
	}
    } elseif {$pathsInfo != ""} {
	multiFetchPaths nupContents $pathsInfo $executableTypes $versions
    }

    #
    # Copy the portable files from another installTop if needed, and execute
    #    the preUpdate commands for each installTop.
    # Note that if any of the commands has an error, the updates will be
    #    aborted.
    #
    set nupCount 0
    foreach top $installTops {
	incr nupCount
	upvar 0 nupContents_$nupCount nupContents
	copyPortableTemps nupContents
	executeUpdateCommands $package "preUpdateCommands" nupContents
    }

    if {!$noNsbChanges} {
	#
	# Install all the files
	#
	set nupCount 0
	foreach top $installTops {
	    incr nupCount
	    upvar 0 nupContents_$nupCount nupContents
	    alwaysEvalFor "error in final installation, results inconsistent!" {} {
		installNupPaths
	    }
	}
    }

    set onlyOneNsbStore 0
    if {([llength $installTops] == 1) &&
	    ([llength $topNsbStoreNames([lindex $installTops 0])] == 1)} {
	set onlyOneNsbStore 1
    }
    global saveUnchangedNsbfiles
    if {!$noNsbChanges || ($onlyOneNsbStore && $saveUnchangedNsbfiles)} {
	#
	# Save all the '.nsb' files
	#
	set nupCount 0
	foreach top $installTops {
	    incr nupCount
	    upvar 0 nupContents_$nupCount nupContents
	    upvar 0 hadPaths_$nupCount hadPaths
	    set warndups 0
	    foreach nsbStoreName $topNsbStoreNames($top) {
		if {$hadPaths || $noNsbChanges} {
		    updatemsg "Saving $nsbStoreName"
		    if {$onlyOneNsbStore} {
			# Save original modification time so an rsync
			#   can be more efficient
			set action rename
		    } else {
			set action copy
		    }
		    notrace {withParentDir {file $action -force $nsbScratch $nsbStoreName}}
		    if {$action == "rename"} {
			removeFromScratchFiles $nsbScratch
		    }
		} elseif {[file exists $nsbStoreName]} {
		    if {$procNsbType == "remove"} {
			updatemsg "Deleting $nsbStoreName"
		    } else {
			updatemsg "Deleting $nsbStoreName because no paths in package"
		    }
		    notrace {file delete $nsbStoreName}
		} elseif {$procNsbType == "remove"} {
		    updatemsg "Package $package was already removed"
		}
	    }
	}

	#
	# Write out registry database changes
	#
	nrdCommitUpdates

    }

    if {$procNsbType == "batchUpdate"} {
	# pushpackage.sh looks for these magic words
	puts "Batch update succeeded"
    }

    #
    # Execute the postUpdateCommands
    #
    set nupCount 0
    foreach top $installTops {
	incr nupCount
	upvar 0 nupContents_$nupCount nupContents
	executeUpdateCommands $package "postUpdateCommands" nupContents 1
	unset nupContents
    }
}

#
# Determine the unique installTops, the nsbStoreNames and relocParams that
#  apply under the installTops, and which executableTypes and versions apply to
#  each nsbStoreName.
#
proc calculateInstallTops {package executableTypes versions} {
    upvar topNsbStoreNames topNsbStoreNames
    upvar storeExecutableTypes storeExecutableTypes
    upvar storeVersions storeVersions
    upvar topRelocParams topRelocParams

    catch {unset storeExecutableTypes storeVersions topNsbStoreNames topRelocParams}
    set installTops ""
    set allNsbStoreNames ""
    foreach executableType $executableTypes {
	set executableType [cleanSubst $executableType]
	foreach version $versions {
	    set version [cleanSubst $version]
	    set installTop [getInstallTop $package $executableType $version]
	    if {![info exists topNsbStoreNames($installTop)]} {
		lappend installTops $installTop
	    }
	    set nsbStoreName [getNsbStoreName $package $executableType $version]
	    luniqueAppend storeExecutableTypes($nsbStoreName) $executableType
	    luniqueAppend storeVersions($nsbStoreName) $version
	    #  it is possible to have multiple nsbStoreNames for the same
	    #  installTop if a user specifies a %E or %V in the nsbStorePath but
	    #  doesn't specify a per-executableType or per-version installTop
	    if {![info exists topNsbStoreNames($installTop)] ||
		    [lsearch -exact $topNsbStoreNames($installTop) \
							$nsbStoreName] < 0} {
		lappend topNsbStoreNames($installTop) $nsbStoreName
		if {[lsearch -exact $allNsbStoreNames $nsbStoreName] >= 0} {
		    nsbderror \
    "May not store '.nsb' file in the same place for different installTops"
		}
		lappend allNsbStoreNames $nsbStoreName
	    }
	    #
	    # calculate relocTop if any
	    #
	    set relocTop [getRelocTop $package $executableType $version]
	    set relocParams ""
	    if {$relocTop != ""} {
		debugmsg "relocTop for installTop $installTop is $relocTop"
		# need to save the relocTop and the parameters needed to
		#   calculate the original installTop, because that can't
		#   be determined at this point during audits
		set relocParams [list $relocTop \
			[list $package $executableType $version]]
	    }
	    # I don't know if it's possible to have multiple relocTops for
	    #   the same installTop but check just in case
	    if {![info exists topRelocParams($installTop)]} {
		set topRelocParams($installTop) $relocParams
	    } elseif {$topRelocParams($installTop) != $relocParams} {
		nsbderror "relocTop+executableType+version expands to more than one value for the same installTop"
	    }
	}
    }
    return $installTops
}

#
# Find existing stored '.nsb' file for package, if any.
#
proc findNsbStoreFiles {package {executableTypes "{*}"} {versions "{*}"}} {
    if {$executableTypes == "{*}"} {
	set executableTypes [getCmdkey executableTypes]
	if {$executableTypes == ""} {
	    set executableTypes [nrdLookup $package executableTypes]
	}
	set executableTypes [cleanSubsts $executableTypes]
    }
    if {$executableTypes == ""} {
	global cfgContents
	if {[info exists cfgContents(executableTypes)]} {
	    set executableTypes $cfgContents(executableTypes)
	} else {
	    set executableTypes [list ""]
	}
    }
    if {$versions == "{*}"} {
	set versions [cleanSubsts [nrdLookup $package versions]]
    }
    if {$versions == ""} {
	set versions [list ""]
    }
    set nameList ""
    foreach executableType $executableTypes {
	foreach version $versions {
	    set nsbStoreName [getNsbStoreName $package $executableType $version]
	    if {[lsearch -exact $nameList $nsbStoreName] >= 0} {
		continue
	    }
	    if {[file exists $nsbStoreName]} {
		lappend nameList $nsbStoreName
	    }
	}
    }
    return $nameList
}

#
# Get rid of nasty characters that could interfere in a filename
#
proc cleanSubst {string} {
    regsub -all {[ /]} $string - string
    return $string
}

#
# Do the same for a list of strings
#
proc cleanSubsts {strings} {
    set newStrings ""
    foreach string $strings {
	lappend newStrings [cleanSubst $string]
    }
    return $newStrings

}

#
# Return valid executableTypes for this package
# If there are registered executableTypes, and the package only contains
#   other types, raise an error
#
proc getExecutableTypes {package nsbContentsName {useAll ""}} {
    upvar $nsbContentsName contents
    global cfgContents

    if {$useAll == ""} {
	set useAll [regexp "%E" [unsubstitutedInstallTop $package]]
    }
    set types [getCmdkey executableTypes]
    if {$types == ""} {
	set types [nrdLookup $package executableTypes]
	set registeredTypes $types
    } else {
	set registeredTypes ""
    }
    set cfgTypes ""
    if {($types == "") && [info exists cfgContents(executableTypes)]} {
	set cfgTypes $cfgContents(executableTypes)
	if {$useAll} {
	    # if installTop has a %E then use all of the config types for which
	    #  the substituted installTop exists
	    if {[info exists contents(version)]} {
		set versions [list $contents(version)]
	    } else {
		set versions [nrdLookup $package versions]
		if {$versions == ""} {
		    set versions [list ""]
		}
	    }
	    set types ""
	    foreach t $cfgTypes {
		foreach v $versions {
		    set stop [getInstallTop $package $t $v]
		    if {[file isdirectory $stop/]} {
			lappend types $t
		    }
		}
	    }
	} else {
	    # no %E in installTop so take them all.   This probably only
	    #   makes sense if there is only one executableType
	    set types $cfgTypes
	}
    }
    if {[info exists contents(executableTypes)]} {
	# intersect the .nsb's executableTypes with the registered ones
	set executableTypes [intersectExecutableTypes $types contents]
	if {($types != "") && ($executableTypes == "")} {
	    if {$registeredTypes != ""} {
		nsbderror "executableType(s) do not match any of those registered for package $package"
	    } elseif {$cfgTypes == ""} {
		# The executable type(s) must have been set on the command line,
                #  but the package has types listed that don't match.
		nsbderror "package $package does not contain selected executableType(s)"
	    } else {
		warnmsg "Warning: executableType(s) do not match any of those in the configuration file"
		# accept them all
		set executableTypes [intersectExecutableTypes "" contents]
	    }
	}
    } else {
	# none were in the .nsb file, take all of them if installTop has a %E
	if {$useAll} {
	    set executableTypes $types
	} else {
	    set executableTypes ""
	}
    }
    if {$executableTypes == ""} {
	set executableTypes [list ""]
    }
    return $executableTypes
}

#
# Return the intersection of the given executable types with those in "contents"
# Also accept a given executable type if it's alias from cfgContents matches
#   a type from "contents", or if the given type matches an alias of the
#   type from "contents" then return the type from "contents" in the
#   given type's place.
# If types is an empty list, accept all from contents.
#
proc intersectExecutableTypes {types contentsName} {
    upvar $contentsName contents
    if {![info exists contents(executableTypes)]} {
	return $types
    }
    set contypes $contents(executableTypes)
    if {($types == "") || ($types == [list ""])} {
	# none were in config file or registry, accept all from contents
	return $contypes
    }
    set cmdtypes $contypes
    if {[info exists contents(precmd_executableTypes)]} {
	# contents(executableTypes) had been overwritten on the
	#   command line, use the originals
	set contypes $contents(precmd_executableTypes)
    }
    global cfgContents
    set executableTypes ""
    foreach t $types {
	if {[lsearch -exact $contypes $t] >= 0} {
	    #
	    # an exact match between requested type and type listed in contents
	    #
	    lappend executableTypes $t
	} elseif {[info exists cfgContents([list executableTypes $t aliases])]} {
	    foreach al $cfgContents([list executableTypes $t aliases]) {
		set idx [lsearch -glob $contypes $al]
		if {$idx >= 0} {
		    #
		    # a match between requested type and an alias; use the
		    #  matched type from contents
		    #
		    set ct [lindex $contypes $idx]
		    lappend executableTypes $ct
		}
	    }
	}
    }
    foreach ct $contypes {
	if {[info exists cfgContents([list executableTypes $ct aliases])]} {
	    foreach al $cfgContents([list executableTypes $ct aliases]) {
		if {[lsearch -glob $types $al] >= 0} {
		    #
		    # a match between an alias of the type in contents and
		    #   the requested type; use the type in contents
		    #
		    lappend executableTypes $ct
		}
	    }
	}
    }
    if {[info exists cfgContents(executableTypes)]} {
	foreach et $cfgContents(executableTypes) {
	    if {[info exists cfgContents([list executableTypes $et aliases])]} {
		set typematched 0
		set ct ""
		foreach al $cfgContents([list executableTypes $et aliases]) {
		    if {[lsearch -glob $types $al] >= 0} {
			set typematched 1
		    }
		    set idx [lsearch -glob $contypes $al]
		    if {$idx >= 0} {
			set ct [lindex $contypes $idx]
		    }
		}
		if {$typematched && ($ct != "")} {
		    #
		    # a requested type matches an alias, and a type from
		    #   contents matches an alias from the same executable type;
		    #  use matched type from contents.
		    #  use luniqueAppend beause it may be a duplicate.
		    #
		    luniqueAppend executableTypes $ct
		}
	    }
	}
    }
    return $executableTypes
}

#
# function analogous to getExecutableTypes for versions
#
proc getVersions {package nsbContentsName} {
    upvar $nsbContentsName contents

    if {[info exists contents(version)]} {
	return [list $contents(version)]
    }
    set versions ""
    if {$package != ""} {
	set versions [nrdLookup $package "versions"]
    }
    if {$versions == ""} {
	return [list ""]
    }
    return $versions
}

#
# function analogous to intersectExecutableTypes for versions
#
proc intersectVersions {versions contentsName} {
    upvar $contentsName contents
    if {[info exists version(contents)]} {
	set version $version(contents)
	if {($versions == "") || ($versions == [list ""]) || 	
				([lsearch -glob $versions $version] >= 0)} {
	    set versions [list $version]
	} else {
	    # it's not clear to me that this is the right thing to do
	    #  in this case but I think so
	    set versions ""
	}
    }
    return $versions
}

#
# Raise an error if required operating system versions are not supported
#   for any executableTypes in the list
#
proc checkOSVersions {executableTypes} {
    global cfgContents nsbContents
    foreach et $executableTypes {
	set min [list executableTypes $et minOSVersion]
	set max [list executableTypes $et maxOSVersion]
	if {[info exists cfgContents($max)] && [info exists nsbContents($min)]} {
	     set have $cfgContents($max)
	     set want $nsbContents($min)
	     if {[compareVersions $have $want] < 0} {
		nsbderror "$et OS version $have too old, must be at least $want"
	    }
	}
	if {[info exists cfgContents($min)] && [info exists nsbContents($max)]} {
	     set have $cfgContents($min)
	     set want $nsbContents($max)
	     if {[compareVersions $have $want] > 0} {
		nsbderror "$et OS version $have too new, must be at most $want"
	    }
	}
    }
}

#
# Return list of required packages from nsbContents that are not installed or
#     not the right version.  For each package, return three items on the list:
#   1. package name
#   2. string reason of why it doesn't meet the requirement
#   3. A substituted url of the 'nsb' files for the package, if supplied
#	and if the package was not registered
#
proc unmetRequirementPackages {executableTypes} {
    global nsbContents
    set rp "requiredPackages"
    if {![info exists nsbContents($rp)]} {
	return ""
    }
    set ans ""
    set package $nsbContents(package)
    foreach p $nsbContents($rp) {
	if {![nrdPackageRegistered $package]} {
	    set nsbUrl ""
	    if {[info exists nsbContents([list $rp $p nsbUrl])]} {
		set nsbUrl [lindex [substituteUrl \
		  $nsbContents([list $rp $p nsbUrl]) $p $executableTypes ""] 0]
	    }
	    lappend ans $p "not registered" $nsbUrl
	    continue
	}
	set versions [nrdLookup $p "versions"]
	if {[info exists nsbContents([list $rp $p minVersion])]} {
	    set minVersion $nsbContents([list $rp $p minVersion])
	    set ok 0
	    foreach version $versions {
		if {[compareVersions $version $minVersion] >= 0} {
		    set ok 1
		    break
		}
	    }
	    if {!$ok} {
		lappend ans $p "version too old, wanted $minVersion" ""
		continue
	    }
	}
	if {[info exists nsbContents([list $rp $p maxVersion])]} {
	    set maxVersion $nsbContents([list $rp $p maxVersion])
	    set ok 0
	    foreach version $versions {
		if {[compareVersions $version $maxVersion] <= 0} {
		    set ok 1
		    break
		}
	    }
	    if {!$ok} {
		lappend ans $p "version too new, wanted $maxVersion" ""
		continue
	    }
	}
	set minGeneratedAt ""
	set maxGeneratedAt ""
	if {[info exists nsbContents([list $rp $p minGeneratedAt])]} {
	    set minGeneratedAt $nsbContents([list $rp $p minGeneratedAt])
	}
	if {[info exists nsbContents([list $rp $p maxGeneratedAt])]} {
	    set maxGeneratedAt $nsbContents([list $rp $p maxGeneratedAt])
	}
	if {($minGeneratedAt != "") || ($maxGeneratedAt != "")} {
	    foreach nsbStoreFile [findNsbStoreFiles $p $executableTypes] {
		catch {unset tmpContents}
		nsbdParseFile $nsbStoreFile "nsb" tmpContents
		set generatedAt $tmpContents(generatedAt)
		if {$minGeneratedAt != ""} {
		    if {[compareTimes $generatedAt $minGeneratedAt] >= 0} {
			set minGeneratedAt ""
			if {$maxGeneratedAt == ""} {
			    break
			}
		    }
		}
		if {$maxGeneratedAt != ""} {
		    if {[compareTimes $generatedAt $maxGeneratedAt] <= 0} {
			set maxGeneratedAt ""
			if {$minGeneratedAt == ""} {
			    break
			}
		    }
		}
	    }
	}
	if {$minGeneratedAt != ""} {
	    lappend ans $p "generatedAt too old, wanted $minGeneratedAt" ""
	    continue
	}
	if {$maxGeneratedAt != ""} {
	    lappend ans $p "generatedAt too new, wanted $maxGeneratedAt" ""
	    continue
	}
    }
    return $ans
}

#
# Return the unsubstituted installTop for package $package
#
proc unsubstitutedInstallTop {package} {
    global cfgContents
    set pkgTop [getCmdkey installTop cfg]
    if {$pkgTop != ""} {
	# installTop set on the command line
	return $pkgTop
    }
    # don't let a relocTop on the command line override an installTop in
    #  the registry or config

    # not set on the command line; merge registry entry and config entry
    set cfgTop ""
    foreach k {installTop relocTop} {
	if {$pkgTop == ""} {
	    set pkgTop [nrdLookup $package $k]
	}
	if {($cfgTop == "") && [info exists cfgContents($k)]} {
	    set cfgTop $cfgContents($k)
	}
    }
    if {$cfgTop == ""} {
	set cfgTop "~/nsbd"
    }
    return [file join $cfgTop $pkgTop]
}

#
# Get the installTop value for this package using given executableType & version
# See the description of the installTop configuration keyword for details.
#
proc getInstallTop {package executableType version} {
    set top [substitutePercents installTop [unsubstitutedInstallTop $package] \
		$package $executableType $version]

    # canonialize the name a little bit for comparisons, and make
    #   sure it ends in a slash
    return [cleanPath $top/]
}

#
# Get the original "installTop" from the '.nsb' file if it was set, and
#   apply substitutions
#
proc getOrigInstallTop {package executableType version} {
    upvar nsbContents nsbContents
    if {[info exists nsbContents(precmd_installTop)]} {
	set origInstallTop $nsbContents(precmd_installTop)
    } elseif {[info exists nsbContents(installTop)]} {
	set origInstallTop $nsbContents(installTop)
    } else {
	return ""
    }

    set top [substitutePercents installTop $origInstallTop \
		$package $executableType $version]
    return [cleanPath $top/]
}

#
# Get the relocTop value for this package using given executableType & version
# Returns empty if none is set.
#
proc getRelocTop {package executableType version} {
    set pkgTop [getCmdkey relocTop cfg]
    if {$pkgTop == ""} {
	# not set on the command line; merge registry & config entries
	global cfgContents

	set pkgTop [nrdLookup $package relocTop]
	if {[info exists cfgContents(relocTop)]} {
	    set cfgTop $cfgContents(relocTop)
	} else {
	    set cfgTop ""
	}
	set pkgTop [file join $cfgTop $pkgTop]
	if {$pkgTop == ""} {
	    return ""
	}
    }

    set top [substitutePercents relocTop $pkgTop \
		$package $executableType $version]
    return [cleanPath $top/]
}
#
# Return the default nsbStorePath
#
proc defaultNsbStorePath {} {
    global cfgContents
    if {[info exists cfgContents(nsbStorePath)]} {
	return $cfgContents(nsbStorePath)
    }
    set nsbdpath $cfgContents(nsbdpath)
    if {![isDirectory $nsbdpath]} {
	return $nsbdpath/
    }
    return $nsbdpath
}

#
# Return the name of the file that the '.nsb' file will be stored under
#   for the given package, executableType and version.
# See the description of the nsbStorePath configuration keyword for details.
#
proc getNsbStoreName {package executableType version} {
    set storePath [nrdLookup $package nsbStorePath]
    if {$storePath == ""} {
	set storePath [defaultNsbStorePath]
    }
    set storePath [substitutePercents nsbStorePath $storePath \
				$package $executableType $version]
    set top [getInstallTop $package $executableType $version]
    set storeDir [file join $top $storePath]
    if {[isDirectory $storePath] || [file isdirectory $storeDir]} {
	return [file join $storeDir ${package}.nsb]
    }
    return ${storeDir}
}

#
# Return extension for given executableType
# If type is "*", return list of all types
#
proc getExecutableTypeExtension {type} {
    global cfgContents
    if {$type == "*"} {
	set extensions ""
	if {[info exists cfgContents(executableTypes)]} {
	    foreach etype $cfgContents(executableTypes) {
		set extkey [list executableTypes $etype extension]
		if {[info exists cfgContents($extkey)] && 
					($cfgContents($extkey) != "")} {
		    luniqueAppend extensions $cfgContents($extkey)
		}
	    }
	}
	return $extensions
    }
    set extkey [list executableTypes [getAliasExecutableType $type] extension]
    if {[info exists cfgContents($extkey)]} {
	return $cfgContents($extkey)
    }
    return ""
}

#
# If the type is an alias, return the real executableType otherwise
#   return the passed-in type
#
proc getAliasExecutableType {type} {
    global cfgContents
    if {[info exists cfgContents(executableTypes)]} {
	foreach t $cfgContents(executableTypes) {
	    if {[info exists cfgContents([list executableTypes $t aliases])]} {
		foreach a $cfgContents([list executableTypes $t aliases]) {
		    if {[string match $a $type]} {
			return $t
		    }
		}
	    }
	}
    }
    return $type
}

#
# Substitute %P, %E, and %V if any in path.
#
proc substitutePercents {var path package executableType version} {
    set executableType [getAliasExecutableType $executableType]
    foreach {subst keyname} "P package E executableType V version" {
	if {[regexp "%$subst" $path]} {
	    set varval [set $keyname]
	    if {$varval == ""} {
		nsbderror "$var $path for package $package contains %$subst and $keyname unknown"
	    }
	    regsub -all "%$subst" $path $varval path
	}
    }
    return $path
}

#
# Substitute %P, %E, and %V if any in url for given package,
#    executableTypes, and versions
# Does not assume that executableTypes and versions are "cleanSubst"ed already
# Returns list of substituted urls
#

proc substituteUrl {url package executableTypes versions} {
    set distributedPackageName [nrdLookup $package distributedPackageName]
    if {$distributedPackageName == ""} {
	set distributedPackageName $package
    }
    regsub -all "%P" $url $distributedPackageName url
    set urls [list $url]
    if {[regexp %V $url]} {
	# add an extra, empty version
	lappend versions ""
	set urls [multiSubstitute %V $urls [cleanSubsts $versions]]
    }
    if {[regexp %E $url]} {
	if {$executableTypes == ""} {
	    nsbderror "No executableTypes in package $package to substitute for %E in $url"
	}
	set urls [multiSubstitute %E $urls [cleanSubsts $executableTypes]]
    }
    return $urls
}

#
# verify that all files at $urls are identical to $localFile
# If one of them is not, return it, otherwise return empty.
#
proc compareUrls {localFile urls} {
    foreach url $urls {
	set scratchName [scratchAddName "ver"]
	urlCopy $url $scratchName "" "-progress urlProgress"
	if {![compareFiles $localFile $scratchName]} {
	    return $url
	}
	scratchClean $scratchName
    }
    return ""
}

#
# verify that all applicable URLs in nsbContents are accessible and
#    match checksum info
#
proc fetchAllNsbContents {executableTypes versions nsbStoreName} {
    global nsbContents nsbNupKeys

    set package $nsbContents(package)

    if {![info exists nsbContents(nsbUrl)]} {
	progressmsg "Note: no nsbUrl keyword, user may not know where to find '.nsb' file"
    } else {
	set differentUrl [compareUrls $nsbStoreName \
			    [substituteUrl $nsbContents(nsbUrl) \
				$package $executableTypes $versions]]
	if {$differentUrl != ""} {
	    nsbderror "file at $differentUrl not identical"
	}
    }

    addKeys $nsbNupKeys nsbContents subContents nsb
    substitutePaths $package nsbContents subContents \
	    					$executableTypes $versions 2
    validatePaths subContents [calculateValidPaths subContents] $executableTypes

    if {![info exists subContents(paths)]} {
	progressmsg "No applicable paths in package"
    } else {
	set mdType $subContents(mdType)
	set pathsInfo ""
	set scratchName [scratchAddName "ver"]
	foreach path $subContents(paths) {
	    if {![info exists subContents([list paths $path length])]} {
		# must be directory or link, skip it
		continue
	    }
	    set expectedMdData [list $subContents([list paths $path length]) \
				    $subContents([list paths $path $mdType])]
	    if {![info exists subContents(urlPresubstitutions)] ||
		    (($subContents(urlPresubstitutions) != "all") &&
		     ($subContents(urlPresubstitutions) != "nsbFile"))} {
		set path $subContents([list paths $path loadPath])
	    }
	    lappend pathsInfo [list $path $scratchName "" "" $expectedMdData]
	}
	multiFetchPaths subContents $pathsInfo $executableTypes $versions
	scratchClean $scratchName
    }
}

#
# Load an old nsb file for comparison if available
# level should be #0 for global oldnsbContents/oldnupContents or 1
#   for local variables in the calling procedure
#
proc loadOldNsbFile {level nsbStoreFile package executableTypes versions} {
    eval uplevel $level "upvar #0 nsbContents_$nsbStoreFile oldnsbContents"
    eval uplevel $level "upvar #0 nupContents_$nsbStoreFile oldnupContents"
    upvar #0 nsbContents_$nsbStoreFile oldnsbContents
    upvar #0 nupContents_$nsbStoreFile oldnupContents

    if {[array exists oldnupContents]} {
	if {[info exists oldnupContents(emptyarray)]} {
	    return
	}
	progressmsg "Reusing previously loaded $nsbStoreFile"
	return
    }

    if {![file exists $nsbStoreFile]} {
	# create the array to avoid going through this again next time
	set oldnupContents(emptyarray) ""
    } else {
	# read old contents into oldnsbContents
	progressmsg "Loading $nsbStoreFile"
	nsbdParseFile $nsbStoreFile "nsb" oldnsbContents
	alwaysEvalFor $nsbStoreFile {} {
	    if {![info exists oldnsbContents(package)]} {
		nsbderror "no package keyword"
	    }
	    set distributedPackageName [nrdLookup $package distributedPackageName]
	    if {$distributedPackageName == ""} {
		set distributedPackageName $package
	    }
	    if {$oldnsbContents(package) != $distributedPackageName} {
		nsbderror "incorrect package: $oldnsbContents(package); expected $distributedPackageName"
	    }
	    set oldnsbContents(package) $package
	}
	applyCmdkeys oldnsbContents nsb
	#
	# intersect the given executableTypes and versions with those in
	#   the old '.nsb' file.
	#
	set executableTypes [intersectExecutableTypes $executableTypes oldnsbContents]
	set versions [intersectVersions $versions oldnsbContents]

	if {[info exists oldnsbContents(paths)]} {
	    alwaysEvalFor $nsbStoreFile {} {
		substitutePaths $package oldnsbContents oldnupContents \
					$executableTypes $versions
	    }
	}
    }

    #
    # Clean out anything in oldnsbContents starting with "paths" to save
    #   memory (which can be quite significant!); it is no longer needed
    #
    foreach name [array names oldnsbContents] {
	if {[lindex $name 0] == "paths"} {
	    unset oldnsbContents($name)
	}
    }
}

#
# Clear the oldnsbContents and oldnupContents arrays because once
#  a package is successfully processed the old ones won't be valid
#  anymore; if they are needed again, they will be reloaded
#
proc clearOldNsbFile {{level "#0"}} {
    upvar $level oldnsbContents oldnsbContents
    upvar $level oldnupContents oldnupContents
    catch {unset oldnsbContents}
    catch {unset oldnupContents}
}

#
# Do any updates that are to be made to the registry database
# Assumes paths have already been loaded into nupContents
#
proc nsbUpdateNrd {nsbScratch package executableTypes versions} {
    global cfgContents nsbContents oldnsbContents oldnupContents
    global nrdKeytable procNsbType
    upvar nupContents nupContents

    if {$procNsbType == "preview"} {
	return
    }
    #
    # Update the registered versions
    #
    if {$nupContents(paths) == ""} {
	# will be deleting, empty package
	set versions ""
    }
    if {[string first "%V" [getNsbStoreName $package "%E" "%V"]] < 0} {
	# there is no %V in the nsbStorePath, so overwrite existing versions
	nrdUpdate $package "set" "versions" $versions
    } else {
	if {[info exists oldnsbContents(version)]} {
	    # NOTE: this should only take effect when removing because on an
	    #   update the old .nsb file can only contain the same version,
	    #   because there's a %V in the nsbStoreName and only one version
	    #   is supported in a .nsb file. 
	    set oldVersion $oldnsbContents(version)
	    if {[lsearch -exact $versions $oldVersion] < 0} {
		# remove old versions that have been deleted
		nrdUpdate $package "delete" "versions" $oldVersion
	    }
	}
	# add any new versions
	foreach version $versions {
	    nrdUpdate $package "add" "versions" $version
	}
    }

    if {$procNsbType == "remove"} {
	# deleting the package, don't do any more to the registry updates
	return
    }

    if {[info exists cfgContents(maintainerUpdatableKeys)]} {
	set updatableKeys $cfgContents(maintainerUpdatableKeys)
	# I don't want to support changing installTop (hard to do, and not
	#   very useful), but I want to display a warning if it changes,
	#   so that's why it's in the loop below.  Make sure it's not
	#   in the updatableKeys list.
	if {[set idx [lsearch -exact $updatableKeys "installTop"]] >= 0} {
	    set updatableKeys [lreplace $updatableKeys $idx $idx]
	}
    } else {
	set updatableKeys "nsbUrl"
    }

    global cmdKeytable
    foreach keyname {nsbUrl maintainers installTop validPaths \
			preUpdateCommands postUpdateCommands} {
	if {[info exists cmdKeytable($keyname)]} {
	    # skip keys which were set on the command line
	    continue
	}
	set lookupVal [nrdLookup $package $keyname]
	if {[lsearch -exact $updatableKeys $keyname] < 0} {
	    # not updatable
	    if {$procNsbType == "batchUpdate"} {
		# don't warn about changes in a "push" operation; the warnings
		#  are for the users and not the maintainers anyway
		continue
	    }
	    set updatable 0
	    # for non-updatable keys, look up value in old .nsb file
	    #  in addition to the database, to warn only about changes
	    if {$keyname == "validPaths"} {
		set oldVal [calculateValidPaths oldnupContents]
	    } elseif {[info exists oldnsbContents($keyname)]} {
		set oldVal $oldnsbContents($keyname)
	    } else {
		set oldVal ""
	    }
	} else {
	    set updatable 1
	    set oldVal $lookupVal
	}
	if {$keyname == "validPaths"} {
	    set newVal [calculateValidPaths nupContents]
	} else {
	    if {![info exists nsbContents($keyname)]} {
		continue
	    }
	    set newVal $nsbContents($keyname)
	}
	if {($newVal == $oldVal) || ($newVal == $lookupVal)} {
	    # no change
	    continue
	}
	if {$nrdKeytable([list packages $keyname])} {
	    # a list - only report things that are added or removed
	    #   relative to both oldVal and lookupVal (which are only
	    #   different if it is a non-maintainerUpdatableKey)
	    set added ""
	    set removed ""
	    set fromTo ""
	    if {!$updatable && ($keyname == "validPaths")} {
		# only warn about ones that don't match wild cards in lookupVal
		foreach val $newVal {
		    if {([lsearch -exact $oldVal $val] < 0) &&
			    ([lpathmatch $lookupVal $val] < 0)} {
			lappend added $val
		    }
		}
	    } else {
		foreach val $newVal {
		    if {([lsearch -exact $oldVal $val] < 0) &&
			    ([lsearch -exact $lookupVal $val] < 0)} {
			lappend added $val
		    }
		}
	    }
	    foreach val $oldVal {
		if {([lsearch -exact $newVal $val] < 0) &&
			([lsearch -exact $lookupVal $val] >= 0)} {
		    lappend removed $val
		}
	    }
	    if {$added != ""} {
		append fromTo " added item(s)\n    [join $added "\n    "]"
		if {$removed != ""} {
		    append fromTo "\n  and"
		}
	    }
	    if {$removed != ""} {
		append fromTo " removed item(s)\n    [join $removed "\n    "]"
	    }
	    if {$fromTo == ""} {
		# no changes to report; perhaps list items were just reordered
		continue
	    }
	} else {
	    # not a list
	    if {$oldVal != ""} {
		set fromTo " changed from\n    $oldVal\n  to\n    $newVal"
	    } else {
		set fromTo "\n  was not set before but is now set to\n    $newVal"
	    }
	}
	if {!$updatable} {
	    set msg "Warning: non-maintainerUpdatableKey \"$keyname\"$fromTo"
	    append msg "\n  in the new $package '.nsb' file; registry not updated"
	    append msg "\n  attempting to continue anyway"
	    warnmsg $msg
	    continue
	}
	# do per key-type checking before accepting the change
	switch $keyname {
	    nsbUrl {
		# make sure that all new nsbUrls are accessible
		set differentUrl [compareUrls $nsbScratch \
				    [substituteUrl $newVal \
					$package $executableTypes $versions]]
		if {$differentUrl != ""} {
		    nsbderror "file at $differentUrl not identical, won't update registered nsbUrl"
		}
	    }
	    maintainers {
		# DWD TO DO
		nsbderror "remotely updating registered maintainers not implemented yet"
	    }
	}
	updatemsg "\"$keyname\" for package $package$fromTo"
	nrdUpdate $package "set" $keyname $newVal
    }
}

#
# initialize permission calculations
#
proc initPathPerms {package} {
    global cfgContents
    upvar pathPermCreateMask createMask
    upvar pathPermUsualPerms usualPerms
    upvar pathPermPatVals patVals

    set createMask $cfgContents(createMask)
    set usualPerms \
	[list "r" [format "0%o" [expr "0444" & ~$createMask]] \
	      "rw" [format "0%o" [expr "0666" & ~$createMask]] \
	      "rwx" [format "0%o" [expr "0777" & ~$createMask]]]
    set pathPerms [nrdLookup $package pathPerms]
    if {[info exists cfgContents(pathPerms)]} {
	set pathPerms [concat $pathPerms $cfgContents(pathPerms)]
    }
    set patVals ""
    foreach pathPerm $pathPerms {
	# this should speed things up a little because this regexp only needs
	#    to be done once on each pathPerm rather than for every path
	set val ""
	regexp "^(\[^ \t\]*)\[ \t\]*(.*)" $pathPerm x pattern val
	lappend patVals $pattern $val
    }
}

#
# Calculate permissions for path
#
proc getPathPerm {path {mode "rwx"}} {
    upvar pathPermUsualPerms usualPerms
    set perm ""
    foreach {m p} $usualPerms {
	if {$m == $mode} {
	    set perm $p
	    break
	}
    }
    if {$perm == ""} {
	upvar pathPermCreateMask createMask
	set perm 0
	foreach {letter adder} {r 4 w 2 x 1} {
	    if {[string first $letter $mode] >= 0} {
		incr perm $adder
	    }
	}
	set perm [format "0%o" [expr "0$perm$perm$perm" & ~$createMask]]
    }

    upvar pathPermPatVals patVals
    foreach {pattern val} $patVals {
	if {[string match $pattern $path]} {
	    set first [string index $val 0]
	    if {$first == "+"} {
		set octperm [expr $perm | "0[string range $val 1 end]"]
	    } elseif {$first == "-"} {
		set octperm [expr $perm & ~"0[string range $val 1 end]"]
	    } else {
		set octperm "0$val"
	    }
	    set perm [format "0%o" [expr $octperm]]
	    break
	}
    }
    return $perm
}

#
# Mask off the setgid bit.  This would be much easier in C of course
#
proc removeSetgidPerm {perm} {
    if {[string length $perm] > 4} {
	return [format "0%o" [expr $perm & 05777]]
    }
    return $perm
}

#
# initialize pathGroups calculations
#
proc initPathGroups {package} {
    upvar pathGroupsPatVals patVals

    set pathGroups [nrdLookup $package pathGroups]
    set patVals ""
    foreach pathGroup $pathGroups {
	# this should speed things up a little because this regexp only needs
	#    to be done once on each pathGroup rather than for every path
	set val ""
	regexp "^(\[^ \t\]*)\[ \t\]*(.*)" $pathGroup x pattern val
	lappend patVals $pattern $val
    }
}

#
# Calculate group for path
#
proc getPathGroup {path} {
    upvar pathGroupsPatVals patVals
    foreach {pattern val} $patVals {
	if {[string match $pattern $path]} {
	    return $val
	}
    }
    return ""
}


#
# Process the already-loaded nsbContents for a single installTop
#   and create the nupContents.  Creating the nupContents consists of 
#   these major steps:
#   1. substitutePaths - copies paths from nsbContents and applies the
#       regSubs and pathSubs substitutions along the way.  The original
#	path gets stored under a "loadPath" subkeyword under the
#	substituted path name in nupContents.
#   2. loadOldNsbFile - loads the previous '.nsb' file to compare the
#	new one to.
#   3. validatePaths - verifies that all the paths being installed are
#	permitted for this package by comparing them against the
#	"validPaths" in the registry database.
#   4. go through each substituted path and remove from nupContents the
#	paths ones that haven't changed from the previously installed
#	'.nsb' file.
#   5. construct the "nupContents(removePaths)" list of paths that were
#	deleted in the new '.nsb' file compared to the old one.
# Return 0 if there were no paths in nsbContents after substitution,
#  otherwise return 1
#
proc makeNupContents {nsbStoreFile nsbScratch installTop \
					executableTypes versions} {
    global nsbContents nsbNupKeys procNsbType noNsbChanges
    upvar nupContents nupContents

    catch {unset nupContents}
    # always set the mdType and paths to something for later convenience
    set nupContents(mdType) md5
    set nupContents(paths) ""
    addKeys $nsbNupKeys nsbContents nupContents nsb

    set package $nupContents(package)
    set nupContents(installTop) $installTop
    if {$executableTypes != ""} {
	set nupContents(executableTypes) $executableTypes
    }
    if {$versions != ""} {
	set nupContents(version) [lindex $versions 0]
    }

    if {$noNsbChanges} {
	#
	# Skip the rest of the processing in this procedure
	#
	set nupContents(removePaths) ""
	return 0
    }

    substitutePaths $package nsbContents nupContents \
				$executableTypes $versions

    loadOldNsbFile #0 $nsbStoreFile $package $executableTypes $versions
    global oldnsbContents oldnupContents


    #
    # Make sure time of new one is newer than the old one, to prevent
    #     replay attacks
    #
    if {[info exists nsbContents(generatedAt)] &&
		    [info exists oldnsbContents(generatedAt)]} {
	set oldtime $oldnsbContents(generatedAt)
	set newtime $nsbContents(generatedAt)
	if {[compareTimes $oldtime $newtime] > 0} {
	    nsbderror "generatedAt time ($newtime) older than time of\n    $nsbStoreFile ($oldtime)"
	}
    }

    #
    # Look first for updates that may be needed to registry database
    #

    nsbUpdateNrd $nsbScratch $package $executableTypes $versions

    if {$procNsbType == "remove"} {
	#
	# Skip most of the rest of the processing in this procedure;
	#   there's no real nsbContents
	#
	set removePaths ""
	if {[info exists oldnupContents(paths)]} {
	    set removePaths $oldnupContents(paths)
	}
	set nupContents(removePaths) [lsort -decreasing $removePaths]
	clearOldNsbFile
	return 0
    }

    progressmsg "Calculating updates to install in $installTop"

    initPathPerms $package
    initPathGroups $package

    #
    # determine which files need to be loaded
    #
    set substitutedPaths ""
    if {![info exists nupContents(paths)]} {
	updatemsg "no paths keyword found"
    } else {
	validatePaths nupContents [nrdLookup $package "validPaths"] $executableTypes
	set mdType $nupContents(mdType)
	set changedPaths ""
	if {[info exists nupContents(paths)]} {
	    set substitutedPaths $nupContents(paths)
	}
	foreach path $substitutedPaths {
	    set pathsTable($path) ""
	    if {[isDirectory $path]} {
		# a directory
		if {[info exists oldnupContents([list paths $path loadPath])]} {
		    unset nupContents([list paths $path loadPath])
		    continue
		}
		# perm is atemporary internal keyword
		set nupContents([list paths $path perm]) [getPathPerm $path]
		# fall through
	    } elseif {[info exists nupContents([list paths $path linkTo])]} {
		# a symbolic link
		set link $nupContents([list paths $path linkTo])
		if {[info exists oldnupContents([list paths $path linkTo])]} {
		    set oldlink $oldnupContents([list paths $path linkTo])
		    if {$link == $oldlink} {
			# hasn't changed, no need to include it
			unset nupContents([list paths $path linkTo])
			unset nupContents([list paths $path loadPath])
			continue
		    }
		}
		# fall through
	    } elseif {[info exists nupContents([list paths $path hardLinkTo])]} {
		# a hard link
		set link $nupContents([list paths $path hardLinkTo])
		if {![info exists nupContents([list paths $link loadPath])] &&
		  [info exists oldnupContents([list paths $path hardLinkTo])]} {
		    set oldlink $oldnupContents([list paths $path hardLinkTo])
		    if {$link == $oldlink} {
			# link hasn't changed and path linked-to hasn't
			#   changed, so no need to include hard link
			unset nupContents([list paths $path hardLinkTo])
			unset nupContents([list paths $path loadPath])
			continue
		    }
		}
		# fall through
	    } else {
		set mode $nupContents([list paths $path mode])
		set perm [getPathPerm $path $mode]
		if {[info exists oldnupContents([list paths $path length])] &&
		    [info exists oldnupContents([list paths $path $mdType])] &&
			($nupContents([list paths $path length]) ==
			    $oldnupContents([list paths $path length])) &&
			($nupContents([list paths $path $mdType]) ==
				$oldnupContents([list paths $path $mdType])) &&
			($perm == [getPathPerm $path \
				$oldnupContents([list paths $path mode])])} {
		    # file is the same as the old one, don't need to update
		    unset nupContents([list paths $path length])
		    unset nupContents([list paths $path $mdType])
		    unset nupContents([list paths $path mode])
		    unset nupContents([list paths $path loadPath])
		    continue
		} else {
		    # perm is a temporary internal keyword
		    set nupContents([list paths $path perm]) $perm
		}
	    }
	    if {[set group [getPathGroup $path]] != ""} {
		# group is a temporary internal keyword
		set nupContents([list paths $path group]) $group
	    }
	    if {![info exists oldnupContents([list paths $path loadPath])]} {
		# new is a temporary internal keyword
		set nupContents([list paths $path new]) ""
	    }
	    lappend changedPaths $path
	}
	set nupContents(paths) $changedPaths
    }

    #
    # determine which files need to be removed.
    # Note that a removed directory does not necessarily mean
    #  that the directory will need to be removed if there are
    #  still files that use the directory.  They are sorted in
    #  decreasing order to make sure all files will be removed
    #  before their enclosing directories.
    #
    set removePaths ""
    if {[info exists oldnupContents(paths)]} {
	foreach path $oldnupContents(paths) {
	    if {![info exists pathsTable($path)]} {
		if {$path != ""} {
		    lappend removePaths $path
		}
	    }
	}
    }
    set nupContents(removePaths) [lsort -decreasing $removePaths]

    clearOldNsbFile

    return [expr {$substitutedPaths != ""}]
}

#
# Find packages that have registry validPaths that overlap the given validPath
#    glob patterns.  Return a list of all overlapping packages.
# Note that general cross-matching of glob patterns is too hard to do, so the
#    "matchpatterns" function makes some assumptions that are generally
#    true in validPaths to make it easier.
#

proc findOverlappingPackages {package patterns} {
    set installTop [unsubstitutedInstallTop $package]
    if {[string first %P $installTop] >= 0} {
	# if installTop includes the package name there can be none
	#   that overlap
	return
    }
    
    set globWildExp {\*|\?|\[|\]}

    #
    # As an optimization, put all the non-wildcard patterns and their
    #   parent directories into an associative array to do a quick match
    #   against the validPaths that also don't have wildcards but may 
    #   be whole directories
    set wildPatterns ""
    foreach pattern $patterns {
	if {![regexp $globWildExp $pattern]} {
	    while {($pattern != ".") && ![info exists knownPaths($pattern)]} {
		set knownPaths($pattern) ""
		set pattern "[file dirname $pattern]/"
	    }
	} else {
	    if {[isDirectory $pattern]} {
		append pattern "*"
	    }
	    lappend wildPatterns $pattern
	}
    }

    # append a star to each directory pattern (those ending with /)
    set allPatterns ""
    foreach pattern $patterns {
	if {[isDirectory $pattern]} {
	    append pattern "*"
	}
	lappend allPatterns $pattern
    }

    set overlappingPackages ""
    set otherPackages [nrdPackages]
    foreach otherPackage $otherPackages {
	set otherTop [unsubstitutedInstallTop $otherPackage]
	if {$otherPackage == $package} {
	    continue
	}
	if {$installTop != $otherTop} {
	    continue
	}
	set overlaps 0
	foreach otherPattern [nrdLookup $otherPackage validPaths] {
	    if {![regexp $globWildExp $otherPattern]} {
		if {[info exists knownPaths($otherPattern)]} {
		    set overlaps 1
		    debugmsg "$package overlaps with $otherPackage non-wild pattern $otherPattern"
		    break
		}
		set patterns $wildPatterns
	    } else {
		set patterns $allPatterns
	    }
	    if {[isDirectory $otherPattern]} {
		append otherPattern "*"
	    }
	    foreach pattern $patterns {
		if {[matchpatterns $pattern $otherPattern]} {
		    set overlaps 1
		    debugmsg "$package pattern $pattern overlaps with $otherPackage pattern $otherPattern"
		    break
		}
	    }
	    if {$overlaps} {
		break
	    }
	}
	if {$overlaps} {
	    lappend overlappingPackages $otherPackage
	}
    }
    return $overlappingPackages
}

#
# Find registered packages that have a validPath that matches the path.
# The path is a full path including the unsubstituted installTop.
# Returns a list where each item is a list of package name and a boolean
#   that is 1 if the validPath was an exact match or 0 if it was a wildcard
#   match.
#
proc findMatchingPackages {path} {
    set matchingPackages ""
    set extension ""
    foreach ext [getExecutableTypeExtension "*"] {
	if {[string match "*$ext*" $path]} {
	    # substitute %X for something most likely to match
	    set extension $ext
	    break
	}
    }
    foreach otherPackage [nrdPackages] {
	set otherTop [unsubstitutedInstallTop $otherPackage]
	if {[info exists matchingTop]} {
	    if {$otherTop != $matchingTop} {
		continue
	    }
	} else {
	    # if the path starts with this otherTop, split the path
	    #   into $matchingPath and the remaining relative path
	    set relPath ""
	    set topLen [string length $otherTop]
	    set relStart [expr {$topLen + 1}]
	    set firstchar [string index $path 0]
	    set patIsRelative \
		    [expr {($firstchar != "/") && ($firstchar != "~")}]

	    if {$otherTop == ""} {
		if {!$patIsRelative} {
		    # otherTop is relative but path is not
		    continue
		}
		# path is relative, no editting needed
		# fall through
	    } elseif {$patIsRelative} {
		# otherTop is not relative but path is
		if {$otherTop != "~/nsbd"} {
		    # otherTop doesn't begin with the default top
		    continue
		}
		# this is the default top, accept a relative path
		# fall through
	    } elseif {[string range $path 0 $topLen] != "$otherTop/"} {
		# path doesn't begin with this otherTop
		continue
	    } else {
		# remove top from the path
		set path [string range $path $relStart end]
	    }
	    set matchingTop $otherTop
	}
	set matches 0
	foreach otherPath [nrdLookup $otherPackage validPaths] {
	    regsub -all "%X" $otherPath $extension otherPath
	    if {[isDirectory $otherPath]} {
		append otherPath "*"
	    }
	    if {[string match $otherPath $path]} {
		set matches 1
		debugmsg "$otherPackage's $otherPath matches $path"
		break
	    }
	}
	if {!$matches} {
	    continue
	}

	if {$otherPath == $path} {
	    # exact match
	    lappend matchingPackages [list $otherPackage 1]
	} else {
	    # wildcard match
	    lappend matchingPackages [list $otherPackage 0]
	}
    }
    return $matchingPackages
}

#
# Look for conflicting paths in other packages at the same installTop
#   as the current package in nupContents.
#
proc findConflictingNupPaths {executableTypes} {
    global cfgContents
    upvar nupContents nupContents

    set checkConflicts "all"
    if {[info exists cfgContents(checkPathConflicts)]} {
	set checkConflicts $cfgContents(checkPathConflicts)
    }
    set checkInstalls 0
    set checkDeletes 0
    switch -- $checkConflicts {
	all {
	    set checkInstalls 1
	    set checkDeletes 1
	}
	installs {
	    set checkInstalls 1
	}
	deletes {
	    set checkDeletes 1
	}
    }
    if {$checkInstalls && (![info exists nupContents(paths)] ||
			    ($nupContents(paths) == ""))} {
	set checkInstalls 0
    }
    if {$checkDeletes && ($nupContents(removePaths) == "")} {
	set checkDeletes 0
    }
    if {!$checkInstalls && !$checkDeletes} {
	return
    }

    set package $nupContents(package)

    set paths ""
    if {$checkInstalls} {
	# When installing, look at only new files, those that weren't in the 
	#  old version of the package.  Used to use the registered validPaths,
	#  but that finds more potentially conflicting packages than necessary.
	if {![info exists nupContents(paths)]} {
	    foreach path $nupContents(paths) {
		if {[info exists nupContents([list paths $path new])]
				&& ![isDirectory $path]} {
		    lappend paths $path
		}
	    }
	}
    }
    if {$checkDeletes} {
	# If doing deleting, can't use registered validPaths because those may
	#   have been changed before the package was updated or may be gone
	#   entirely.  Also, because of the feature that permits parent 
	#   directories of valid paths to be included in "paths", remove all 
	#   directories from the "removePaths" list when looking for overlaps.
	#   Unfortunately, this list can get quite long and it needs to be
	#   compared with all the validPaths of all other packages, but I don't
	#   see anyway to reduce the length.  At least it beats having to 
	#   actually read in the '.nsb' files of the other packages, and
	#   findOverlappingPackages has been optimized to handle long lists
	#   of paths.
	#
	foreach path $nupContents(removePaths) {
	    if {![isDirectory $path]} {
		lappend paths $path
	    }
	}
    }

    foreach otherPackage [findOverlappingPackages $package $paths] {
	#
	# Found a potentially conflicting package (validPaths cross)
	# Look for actually conflicting paths
	#

	set otherVersions [nrdLookup $otherPackage versions]
	set nsbStoreFiles [findNsbStoreFiles $otherPackage \
					$executableTypes $otherVersions]
	if {$nsbStoreFiles == ""} {
	    continue
	}
	if {[llength $nsbStoreFiles] != 1} {
	    #
	    # This should be implemented someday; can happen if other package
	    #   has multiple versions installed under the same installTop.
	    # Should also look for conflicts between other versions of
	    #   the current package under the same installTop.
	    #
	    nsbderror "store path for $otherPackage ambiguous:\n  $nsbStoreFiles"
	}
	loadOldNsbFile 1 [lindex $nsbStoreFiles 0] $otherPackage $executableTypes $otherVersions

	if {$checkInstalls} {
	    foreach path $nupContents(paths) {
		if {[isDirectory $path]} {
		    # directories are allowed to conflict
		    continue
		}
		if {[info exists oldnupContents([list paths $path loadPath])]} {
		    nsbderror "$path already installed by package $otherPackage"
		}
	    }
	}
	if {$checkDeletes} {
	    set removePaths ""
	    foreach path $nupContents(removePaths) {
		if {[info exists oldnupContents([list paths $path loadPath])] &&
			![isDirectory $path]} {
		    progressmsg "Skipping delete of $path because in package $otherPackage"
		    continue
		}
		lappend removePaths $path
	    }
	    set nupContents(removePaths) $removePaths
	}
    }
}

#
# Substitute all paths in the fromContents table and load them into
#   the paths keyword in the toContents table.  Also add the internal keyword
#   mdType with the message digest type into the toContents table. 
#   Also apply local substitutions to validPaths in fromContents if any.
# If substituteLevel is 0, do all normal substitutions.  If 1 or more, ignore 
#  duplicate paths. If 2 or more, don't include local config and registry
#  substitutions.  If 3, store the reverse lookup on loadPaths in addition to
#  the forward lookup.
#
proc substitutePaths {package fromContentsName toContentsName \
				executableTypes versions {substituteLevel 0}} {
    upvar $fromContentsName fromContents
    upvar $toContentsName toContents

    if {![info exists fromContents(paths)]} {
	return
    }
    set ignoreDups 0
    set contentsOnly 0
    if {$substituteLevel > 0} {
	set ignoreDups 1
	if {$substituteLevel > 1} {
	    set contentsOnly 1
	}
    }

    initPathSubstitutions $package fromContents $executableTypes $versions \
		$contentsOnly
    set mdType ""
    set toContents(mdType) ""
    global knownMdTypes
    foreach path $fromContents(paths) {
	if {[set msg [relativePathCheck $path]] != ""} {
	    nsbderror $msg
	}
	set ans [substitutePath $path]
	set nonPortable [lindex $ans 0]
	set sPath [lindex $ans 1]
	if {$sPath == ""} {
	    # not applicable to this update
	    continue
	}
	if {[set msg [relativePathCheck $sPath]] != ""} {
	    nsbderror $msg
	}
	if {$nonPortable} {
	    # the nonPortable keyword is temporary and internal
	    set toContents([list paths $sPath nonPortable]) ""
	}

	# Note: the "loadPath" and "backupPath" keywords are temporary and
	#   internal, not defined in the nup fileType tables so they will
	#   never be written out to a file
	if {[info exists toContents([list paths $sPath loadPath])] &&
							    !$ignoreDups} {
	    if {[isDirectory $sPath]} {
		# both are directories
		# silently allow duplicate directories for convenience
		#   of maintainers who may store original files in more
		#   than one source directory that get substituted into
		#   the same destination but don't have conflicting files
		continue
	    }
	    # both are files
	    set prevPath $toContents([list paths $sPath loadPath])
	    nsbderror "both $prevPath and $path install at $sPath"
	}

	if {[isDirectory $sPath]} {
	    set fPath [string range $sPath 0 [expr {[string length $sPath] - 2}]]
	    if {[info exists toContents([list paths $fPath loadPath])]} {
		# this one's a directory and the other's a file
		set prevPath $toContents([list paths $fPath loadPath])
		# this message will end in a trailing slash
		nsbderror "$prevPath and $path both install at directory $sPath"
	    }
	    # fall through
	} elseif {[info exists toContents([list paths $sPath/ loadPath])]} {
	    # this one's a file and the other's a directory
	    set prevPath $toContents([list paths $sPath/ loadPath])
	    # this message will not end in a trailing slash
	    nsbderror "$prevPath and $path both install at directory $sPath"
	} elseif {[info exists fromContents([set plinkType [list paths $path \
						[set linkType linkTo]]])] ||
		  [info exists fromContents([set plinkType [list paths $path \
						[set linkType hardLinkTo]]])]} {
	    # a link
	    set link $fromContents($plinkType)
	    if {[set msg [relativePathCheck $link]] != ""} {
		nsbderror $msg
	    }
	    set ans [substitutePath $link]
	    set nonPortable [lindex $ans 0]
	    set link [lindex $ans 1]
	    if {$link == ""} {
		# not applicable to this update
		continue
	    }
	    if {[set msg [relativePathCheck $link]] != ""} {
		nsbderror $msg
	    }
	    if {$nonPortable} {
		set toContents([list paths $sPath nonPortable]) ""
	    }
	    set toContents([list paths $sPath $linkType]) $link
	    # fall through
	} elseif {![info exists fromContents([set plength \
				    [list paths $path length]])]} {
	    nsbderror "no length for file $path"
	} elseif {[if {$mdType == ""} {
			# figure out which message digest type to use
			foreach t $knownMdTypes {
			    if {[info exists fromContents([list paths $path $t])]} {
				set mdType $t
				set toContents(mdType) $mdType
				break
			    }
			}
		    }
		    expr {$mdType == ""}]} {
	    nsbderror "no message digest for file $path of one of $knownMdTypes"
	} elseif {![info exists fromContents([set pmdType \
				    [list paths $path $mdType]])]} {
	    nsbderror "no message digest of type $mdType for file $path"
	} else {
	    # copy the length and message digest to toContents, even though
	    #  they are temporary and internal and not officially
	    #  part of the toContents
	    set toContents([list paths $sPath length]) $fromContents($plength)
	    set toContents([list paths $sPath $mdType]) $fromContents($pmdType)
	    # same goes for mode, and insert a default if missing
	    if {[info exists fromContents([set pmode \
				    [list paths $path mode]])]} {
		set toContents([list paths $sPath mode]) $fromContents($pmode)
	    } else {
		# fill in default
		set toContents([list paths $sPath mode]) "rw"
	    }
	    # copy the mtime too if it is there
	    if {[info exists fromContents([set pmtime \
				    [list paths $path mtime]])]} {
		set toContents([list paths $sPath mtime]) $fromContents($pmtime)
	    }
	    # fall through
	}
	set toContents([list paths $sPath loadPath]) $path
	lappend toContents(paths) $sPath
	if {$substituteLevel > 2} {
	    set toContents([list loadPaths $path path]) $sPath
	}
	set bPath [backupPath $sPath]
	if {$bPath != ""} {
	    if {[set msg [relativePathCheck $bPath]] != ""} {
		nsbderror $msg
	    }
	    set toContents([list paths $sPath backupPath]) $bPath
	}
    }

    if {[info exists fromContents(validPaths)]} {
	# apply only local substitutions to supplied validPaths
	#  by not passing in "fromContents" to initPathSubstitutions
	initPathSubstitutions $package bogusContents \
			$executableTypes $versions $contentsOnly
	set newpaths ""
	foreach path $fromContents(validPaths) {
	    set ans [lindex [substitutePath $path] 1]
	    if {$ans != ""} {
		lappend newpaths $ans
	    }
	}
	if {$newpaths == ""} {
	    # they were all substituted away which means they must have been
	    #   moved to the top level by the local substitutions; allow all
	    set newpaths [list "*"]
	}
	set toContents(validPaths) $newpaths
    }
}

#
# Do loop-invariant calculating for substitutions to avoid doing them
#   on every path.  Assumes called from the same proc as substitutePath
#   by saving cross-routine data in an "upvar" rather than a global.
# To not include local config and registry substitutions, set contentsOnly
#   to 1.  To not include package nrdLookup substitutions, pass in an empty
#   package. To not include nsbContents substitutions, pass in an empty array
#   as the nsbContents.
# Generates two lists, PathSubstitutions and BackupSubstitutions, that are
#  stored in the context of the function that calls this one.
#  PathSubstitutions is a list of substitutions to apply, each item being
#    a list of these 4 items:
#    1. matchLen - set to the length of string to match when it is a pathSubs
#	substitution with no wildcards, otherwise 0.  pathSubs that do
#	contain wildcards are converted internally into regSubs (because TCL
#       does not contain a substitution function for glob patterns), so
#       whenever matchLen is 0 it is considered to be a regular expression.
#       Conversely, where possible regSubs are converted internally to a fixed
#       length substitution for speed.
#    2. kind - indicates the kind of substitution to perform:
#	  0 - simple substitution, with no %E or %V 
#	  1 - normal substitution
#	  2 - a deletion, meaning a match can completely eliminate the path,
#		distinguished from a normal substitution as an optimization
#    3. matchPart - string or expression to match
#    4. subPart - string or expression to substitute for the matched part
#  BackupSubstitutions is used for implementing "backupSubs" and is a list
#    of substitutions of only two items, the matchPart and the subPart, and
#    are always regular expressions.
#
proc initPathSubstitutions {package nsbContentsName executableTypes versions
					    {contentsOnly 0}} {
    upvar $nsbContentsName contents
    upvar PathSubstitutions pathSubstitutions
    upvar BackupSubstitutions backupSubstitutions
    global cfgContents

    set otherversions ""
    set otherexecutableTypes ""
    if {$contentsOnly == 0} {
	#
	# Calculate the otherexecutableTypes, for use in deleting paths
	#   that are not applicable.  If the precmd_ form is available,
	#   use it since it was the original from before the command line
	#   overwrote it
	set allexecutableTypes ""
	if {[info exists contents(precmd_executableTypes)]} {
	    set allexecutableTypes $contents(precmd_executableTypes)
	} elseif {[info exists contents(executableTypes)]} {
	    set allexecutableTypes $contents(executableTypes)
	}
	foreach type $allexecutableTypes {
	    if {[lsearch -exact $executableTypes $type] < 0} {
		lappend otherexecutableTypes $type
	    }
	}
    }

    #
    # Calculate the substitutions and deletions to perform.
    # Order is very important for pathSubs and regSubs, but backupSubs
    #   is independent of the other two.
    # backupSubs isn't supported in "contents", but it doesn't hurt
    #   to look for it here because the parser will never put them into
    #   "contents" even if it is in the original file.
    #
    set pathSubstitutions ""
    set backupSubstitutions ""
    if {$contentsOnly == 1} {
	set sources contents
    } else {
	set sources {contents nrdLookup cfgContents}
    }
    foreach source $sources {
	foreach keyname {pathSubs regSubs backupSubs} {
	if {$source == "nrdLookup"} {
	    if {$package == ""} {
		    set subs ""
		} else {
		    set subs [nrdLookup $package $keyname]
		    if {($package == "nsbd") && ($keyname == "backupSubs") &&
								($subs == "")} {
			# default backupSubs for special "nsbd" package
			set subs [list "bin/nsbd$ lib/nsbd/oldnsbd"]
		    }
		}
	    } else {
		set contname "${source}($keyname)"
		if {[info exists $contname]} {
		    set subs [set $contname]
		} else {
		    set subs ""
		}
	    }
	    set singularKey [string range $keyname 0 \
				[expr [string length $keyname] - 2]]
	    if {$keyname == "regSubs"} {
		# convert all wildcards in the executableTypes, if any,
		#   from glob style into regexp style.  This has a side
		#   effect so it is important that executableTypes aren't
		#   used later in this function and that regSubs are
		#   processed after pathSubs.
		set newtypes ""
		foreach t $executableTypes {
		    lappend newtypes [glob2regexp $t]
		}
		set executableTypes $newtypes
	    }
	    foreach sub $subs {
		# Treat the substitution as a string rather than a list
		#  because don't want TCL to interpret any special
		#  characters.  The first whitespace separates the
		#  match part from the substitute part.
		regexp "^(\[^ \t\]*)\[ \t\]*(.*)" $sub x matchPart subPart

		# substitute %P
		regsub -all "%P" $matchPart $package matchPart

		if {$keyname == "backupSubs"} {
		    lappend backupSubstitutions $matchPart $subPart
		    debugmsg "will apply $singularKey \"$matchPart\" => \"$subPart\""
		    continue
		}
		set useRegexp 1
		if {$keyname == "pathSubs"} {
		    if {[regexp {\*|\?} $matchPart]} {
			# Convert internally into a regular expression, mainly
			#   because the glob function ([string match...]) can't
			#   do substitutions and can't tell us how much of the
			#   string matched the glob expression.
			if {[isDirectory $matchPart]} {
			    set matchPart "^[glob2regexp $matchPart]"
			} else {
			    set matchPart "^[glob2regexp $matchPart](/|\$)"
			    set subPart "$subPart\\1"
			}
		    } else {
			# regular expressions are very expensive, especially
			#  in tcl 8.3, so avoid them when possible.
			set useRegexp 0
		    }
		} else {
		    # regSubs
		    if {([string index $matchPart 0] == "^") &&
			    ![regexp {\[|\]|\*|\(|\)|[^\\]\.} $matchPart]} {
			set end [string length $matchPart]
			incr end -1
			set lastc [string index $matchPart $end]
			if {($lastc == "/") || ($lastc == "$")} {
			    # convert into match-type because it's faster
			    set useRegexp 0
			    if {$lastc == "$"} {
				incr end -1
			    }
			    set matchPart [string range $matchPart 1 $end]
			    regsub -all {\\} $matchPart "" matchPart
			}
		    }
		}

		if {$useRegexp} {
		    set subtype "$singularKey regexp"
		} else {
		    set subtype "$singularKey match"
		}

		# substitute %E and %V
		# "kind" is set to 0 if there are no %E or %V substitutions,
		#   1 if it is a substitution, or 2 if it is a deletion
		set kind 0
		set matchParts [list $matchPart]
		set othermatchParts ""
		foreach {subst listname} {E executableTypes V versions} {
		    if {[regexp %$subst $matchPart]} {
			set kind 1
			if {$subst == "E" && ([set $listname] == "")} {
			    nsbderror "a substitution contains %E but there are no executableTypes selected"
			}
			if {$matchParts == ""} {
			    set matchParts [list $matchPart]
			}
			set matchParts [multiSubstitute %$subst \
					    $matchParts [set $listname]]

			if {$othermatchParts == ""} {
			    set othermatchParts [list $matchPart]
			}
			set othermatchParts [multiSubstitute %$subst \
					$othermatchParts [set other$listname]]
		    }
		}
		foreach match $matchParts {
		    if {$useRegexp} {
			set matchLen 0
			if {($subPart == "") && ([string index $match 0] == "^")} {
			    set end [expr {[string length $match] - 1}]
			    if {[string index $match $end] == "$"} {
				# This results in using regexp instead of regsub
				#   and that's more efficient in space and time
				#   especially in tcl 8.3
				lappend pathSubstitutions $matchLen 2 $match ""
				debugmsg "will apply $subtype deletion \"$match\""
				continue
			    }
			}
		    } else {
			set matchLen [string length $match]
		    }
		    lappend pathSubstitutions $matchLen $kind $match $subPart
		    debugmsg "will apply $subtype \"$match\" => \"$subPart\""
		}
		foreach match $othermatchParts {
		    if {$useRegexp} {
			set matchLen 0
		    } else {
			set matchLen [string length $match]
		    }
		    lappend pathSubstitutions $matchLen 2 $match ""
		    debugmsg "will apply $subtype deletion \"$match\""
		}
	    }
	}
    }
}

#
# Apply substitutions to the path.
# A substitution may result in a path being deleted entirely,
#  in which case an empty string is returned.
# Otherwise, returns a list of two items:
#  1) a boolean which is set to 0 if the path is portable, 1 if not portable
#  2) the substituted path
# If no substitutions are applicable, return the path unchanged.
#  
proc substitutePath {path} {
    upvar PathSubstitutions pathSubstitutions

    set nonPortable 0
    set changed 0
    set orgPath $path
    foreach {matchLen kind matchPart subPart} $pathSubstitutions {
	if {$matchLen != 0} {
	    # use exact matching
	    set pathLen [string length $path]
	    set endIndex [expr $matchLen - 1]
	    if {(($pathLen == $matchLen) && ($matchPart == $path)) ||
		 (($pathLen > $matchLen) && 
		    ([string range $path 0 $endIndex] == "$matchPart") &&
			(([string index $path $matchLen] == "/") ||
			    ([string index $matchPart $endIndex] == "/")))} {
		if {$kind == 2} {
		    return ""
		}
		if {$kind == 1} {
		    set nonPortable 1
		}
		set path "$subPart[string range $path $matchLen end]"
		set changed 1
	    }
	} else {
	    # use regular expressions
	    if {$kind == 2} { # a deletion
		if {[regexp -- $matchPart $path]} {
		    return ""
		}

	    } elseif {[notrace {regsub -all -- $matchPart $path $subPart path}]} {
		set changed 1
		if {$kind == 1} {
		    set nonPortable 1
		}
	    }
	}
    }
    if {$changed && ($path != "")} {
	set path [cleanPath $path]
	checkSubstitution $orgPath $path
    }
    return [list $nonPortable $path]
}

#
# Check to see if a substitution caused a "sex change" from a directory
#   to a file or vice versa
#
proc checkSubstitution {orgPath path} {
    set odir [isDirectory $orgPath]
    set ndir [isDirectory $path]
    if {$odir && !$ndir} {
	nsbderror "substitution on $orgPath removed trailing slash"
    }
    if {!$odir && $ndir} {
	nsbderror "substitution on $orgPath added trailing slash"
    }
}

#
# return a backup path for $path if there is any, or empty if there is none
#
proc backupPath {path} {
    upvar BackupSubstitutions backupSubstitutions

    set changed 0
    set orgPath $path
    foreach {matchPart subPart} $backupSubstitutions {
	if {[notrace {regsub -all -- $matchPart $path $subPart path}]} {
	    set changed 1
	}
    }
    if {$changed && ($path != "")} {
	checkSubstitution $orgPath $path
	return $path
    }
    return ""
}

#
# Calculate which paths should be considered valid for the
#   package in the contentsName table: validPaths are any
#   directory explicitly included plus any files that are not under
#   one of those directories.  Assumes substitutePaths has already
#   been called in the paths in contentsName.
#
proc calculateValidPaths {contentsName {pathsType "paths"}} {
    upvar $contentsName contents
    if {[info exists contents(validPaths)]} {
	return $contents(validPaths)
    }
    if {![info exists contents($pathsType)]} {
	return
    }
    return [collapsePaths $contents($pathsType)]
}


#
# Remove any files from "paths" that are under directories also in the list
#
proc collapsePaths {paths} {
    set collapsedPaths ""
    foreach path $paths {
	if {[isDirectory $path]} {
	    # a directory.  Remove any existing paths that are under
	    #  $path.  This is defensive coding, since normally the
	    #  directory will come before the paths anyway.
	    set newPaths ""
	    foreach collapsedPath $collapsedPaths {
		if {[string first $path $collapsedPath] != 0} {
		    lappend newPaths $collapsedPath
		}
	    }
	    set collapsedPaths $newPaths
	}
	set gotmatch 0
	foreach collapsedPath $collapsedPaths {
	    if {($collapsedPath == $path) || ([isDirectory $collapsedPath] &&
				([string first $collapsedPath $path] == 0))} {
		set gotmatch 1
		break
	    }
	}
	if {!$gotmatch} {
	    lappend collapsedPaths $path
	}
    }
    return $collapsedPaths
}

#
# Remove directories from the list that only have other directories
#   below them
#
proc collapseNonDirPaths {paths} {
    # intend to implement this someday as a better alternative to
    #  collapsePaths
}

#
# validate that the path is valid for validPaths
# If it is not, raise an error
#
proc validatePath {path validPaths} {
    if {[isDirectory $path]} {
	set pathStar "${path}*"
    } else {
	set pathStar ""
    }
    foreach vp $validPaths {
	if {[isDirectory $vp]} {
	    append vp "*"
	}
	if {[string match $vp $path]} {
	    return
	}
	if {($pathStar != "") && [string match $pathStar $vp]} {
	    # also allow directories that are the parents of registered
	    #   validPaths, for the convenience of maintainers who may
	    #   want to include a parent directory because it's simpler
	    #   than explicitly listing subdirectories
	    return
	}
    }
    nsbderror "$path does not match any of the validPaths"
}

#
# Validate that all paths in contents table are within validPaths
# Raise an error if one doesn't match
#
proc validatePaths {contentsName validPaths executableTypes} {
    upvar $contentsName contents
    global procNsbType
    if {($validPaths == "") && ($procNsbType == "preview")} {
	return
    }
    if {![info exists contents(paths)]} {
	return
    }
    if {($validPaths == "*") || ($validPaths == ".")} {
	# checking '*' here is just a shortcut
	# checking '.' here is obsolete but for backward compatibility
	return
    }
    if {[regexp %X $validPaths]} {
	set extensionType ""
	set extension ""
	foreach type $executableTypes {
	    set ext [getExecutableTypeExtension $type]
	    if {$extensionType != ""} {
		if {$ext != $extension} {
		    nsbderror "validPaths contains %X but there is ambiguity between types $extensionType and $type"
		}
	    } else {
		set extension $ext
		set extensionType $type
	    }
	}
	regsub -all %X $validPaths $extension validPaths
    }
    foreach path $contents(paths) {
	# Validate each path.
	# Also need to validate the link targets to prevent security holes,
	#   for example if someone symlinks in a directory outside of their
	#   validPaths and then tries to install a file below that (which is
	#   not possible with an nsbd-generated '.nsb' file but someone could
	#   create such a '.nsb' file by hand)
	# Need to make sure backupPath is included in validPaths for
	#   checking conflicts between packages and for auditing
	#
	set plist [list paths $path "linkTo"]
	if {[info exists contents($plist)]} {
	    # symbolic links can be directories so try with and without
	    #  trailing slash
	    if {[catch {validatePath "$path/" $validPaths}]} {
		validatePath $path $validPaths
	    }
	    set plink $contents($plist)
	    if {[catch {validatePath "$plink/" $validPaths}]} {
		validatePath $plink $validPaths
	    }
	} else {
	    validatePath $path $validPaths
	    foreach subkey {hardLinkTo backupPath} {
		set plist [list paths $path $subkey]
		if {[info exists contents($plist)]} {
		    validatePath $contents($plist) $validPaths
		}
	    }
	}
    }
}

#
# Preview all the paths listed in nupContents 
#
proc previewNupPaths {} {
    upvar nupContents nupContents

    set package $nupContents(package)
    set installTop $nupContents(installTop)

    set firstmsg "Install top $installTop"
    set removedPaths ""
    foreach path $nupContents(paths) {
	set toPath [file join $installTop $path]
	if {[info exists nupContents([list paths $path backupPath])]} {
	    if {[file exists $toPath]} {
		set bPath $nupContents([list paths $path backupPath])
		previewNupUpdatemsg "Would back up $path to $bPath"
	    }
	}
	set groupmsg ""
	if {[info exists nupContents([list paths $path group])]} {
	    set groupmsg " group $nupContents([list paths $path group])"
	}
	if {[isDirectory $path]} {
	    if {[robustFileType $toPath] != "directory"} {
		set perm $nupContents([list paths $path perm])
		previewNupUpdatemsg "Would make directory $path mode $perm$groupmsg"
	    }
	} elseif {[info exists nupContents([list paths $path linkTo])]} {
	    set link $nupContents([list paths $path linkTo])
	    previewNupUpdatemsg "Would link $path to $link"
	    if {[robustFileType $toPath] == "directory"} {
		# keep track of directories deleted so we don't try to
		#   remove files under it later
		lappend removedPaths "$path/*"
	    }
	} elseif {[info exists nupContents([list paths $path hardLinkTo])]} {
	    set link $nupContents([list paths $path hardLinkTo])
	    previewNupUpdatemsg "Would hardlink $path to $link"
	} else {
	    set perm $nupContents([list paths $path perm])
	    previewNupUpdatemsg "Would install $path mode $perm$groupmsg"
	}
    }
    foreach path $nupContents(removePaths) {
	set skip 0
	foreach removedPath $removedPaths {
	    if {[string match $removedPath $path]} {
		debugmsg "skipping remove of $path because matched $removedPath"
		set skip 1
		break
	    }
	}
	if {$skip} {
	    continue
	}
	set toPath [file join $installTop $path]
	if {[isDirectory $path]} {
	    if {[robustFileType $toPath] == "directory"} {
		previewNupUpdatemsg "Would delete $path if empty"
	    }
	} else {
	    # silently skip deleting a file if its parent directory has been
	    #   deleted or it has turned into a directory
	    if {[file isdirectory [file dirname $toPath]] &&
		    ([robustFileType $toPath] != "directory")} {
		previewNupUpdatemsg "Would delete $path"
	    }
	}
    }
    if {$firstmsg != ""} {
	progressmsg "No updates for files in package for install top $installTop"
    }

}

proc previewNupUpdatemsg {msg} {
    uplevel {
	if {$firstmsg != ""} {
	    progressmsg $firstmsg
	    set firstmsg ""
	}
    }
    progressmsg $msg
}


#
# Return a path to $link relative to $relativePath.
#  $link is given as being relative to the top level.  
#  First, remove all common directory components.
#  Then, for each directory component remaining in
#  relativePath, prepend a "../".
#
proc relativeLinkPath {link relativePath} {
    set splitLink [split $link "/"]
    set splitPath [split $relativePath "/"]
    set endLink [expr [llength $splitLink] - 1]
    set endPath [expr [llength $splitPath] - 1]
    set idx 0
    while {($idx < $endLink) &&
		([lindex $splitLink $idx] == [lindex $splitPath $idx])} {
	incr idx
    }
    set link [join [lrange $splitLink $idx end] "/"]
    if {$link == "."} {
	set link ""
    }
    set dots ""
    while {$idx < $endPath} {
	append dots "../"
	incr idx
    }
    set link "$dots$link"
    if {$link == ""} {
	return "."
    }
    return $link
}

#
# Return installTmp for installTop
#
proc getInstallTmp {installTop} {
    global cfgContents
    if {[info exists cfgContents(installTmp)]} {
	set topdir $cfgContents(installTmp)
    } else {
	set topdir ".nsbdtmp"
    }
    return [file join $installTop $topdir]
}

#
# Return temporaryTop for installTop and package
#
proc getTemporaryTop {installTop package} {
    return [file join [getInstallTmp $installTop] $package]
}

# Append all the information needed to fetch files into temporary directories
#  to the pathsInfo list, of the form needed by urlMultiMdCopy.  If a file
#  is portable and is retrieved in one of the previous nupContents, only
#  note the other directory into which it is retrieved.

proc getNupPathsInfo {nupCount pathsInfoName executableTypes versions relocParams} {
    upvar nupContents_$nupCount nupContents
    upvar $pathsInfoName pathsInfo

    set package $nupContents(package)
    set installTop $nupContents(installTop)
    set temporaryTop [getTemporaryTop $installTop $package]
    set nupContents(temporaryTop) $temporaryTop
    set mdType $nupContents(mdType)

    set relocTop [lindex $relocParams 0]
    set origInstallTop ""
    if {$relocTop != ""} {
	upvar nsbContents nsbContents
	set origInstallTop [eval "getOrigInstallTop [lindex $relocParams 1]"]
	if {($origInstallTop == "") || ($origInstallTop == $relocTop)} {
	    set relocTop ""
	}
    }
    set reloc "$origInstallTop=$relocTop"
    set revreloc "$relocTop=$origInstallTop"
    set nupContents(loadReloc) $reloc
    set nupContents(loadRevreloc) $revreloc

    set usingRsync [isRsyncFetch nupContents]

    set urlPresubstitutions ""
    if {[info exists nupContents(urlPresubstitutions)]} {
	set urlPresubstitutions $nupContents(urlPresubstitutions)
	if {$urlPresubstitutions == "nsbFile"} {
	    global cfgContents
	    set gotone 0
	    foreach keyname {pathSubs regSubs} {
		if {[info exists cfgContents($keyname)] ||
			[nrdLookup $package $keyname] != ""} {
		    set gotone 1
		    break
		}
	    }
	    if {!$gotone} {
		# there were no non nsb-file substitutions so we don't
		#   need to go through the overhead of calculating
		#   substitutions without them; treat it like an "all"
		set urlPresubstitutions "all"
	    } else {
		global nsbContents
		substitutePaths $package nsbContents subContents \
				$executableTypes $versions 3
	    }
	}
    }

    foreach path $nupContents(paths) {
	if {[isDirectory $path]} {
	    continue
	}
	if {[info exists nupContents([list paths $path linkTo])] ||
		[info exists nupContents([list paths $path hardLinkTo])]} {
	    continue
	}
	if {![info exists nupContents([list paths $path nonPortable])]} {
	    # Only load the portable files once
	    set gotit 0
	    for {set n 1} {$n < $nupCount} {incr n} {
		upvar nupContents_$n otherNupContents
		if {[info exists \
			otherNupContents([list paths $path loadPath])]} {
		    set nupContents([list paths $path otherLoadPath]) \
			[file join $otherNupContents(temporaryTop) \
			    $otherNupContents([list paths $path loadPath])]
		    if {$otherNupContents(loadRevreloc) != $revreloc} {
			# going to have to undo that reloc and redo with
			#   this reloc in order to duplicate the files
			set nupContents([list paths $path otherRevreloc]) \
				$otherNupContents(loadRevreloc)
		    }
		    set gotit 1
		    break
		}
	    }
	    if {$gotit} {
		continue
	    }
	}
	set expectedMdData [list $nupContents([list paths $path length]) \
				$nupContents([list paths $path $mdType])]
	if {$urlPresubstitutions == "all"} {
	    set fromPath $path
	    set nupContents([list paths $path loadPath]) $fromPath
	} elseif {$urlPresubstitutions == "nsbFile"} {
	    set loadPath $nupContents([list paths $path loadPath])
	    set fromPath $subContents([list loadPaths $loadPath path])
	    set nupContents([list paths $path loadPath]) $fromPath
	} else {
	    set fromPath $nupContents([list paths $path loadPath])
	}

	#
	# If not using rsync, check for files transferred from a previously
	#   aborted run.
	# If using rsync, let it use its own algorithms if there are files
	#   left over from a previously aborted run.  This is especially
	#   important when relocating things because nsbd doesn't do the
	#   relocation when using rsync until the transfers are complete, and
	#   reverse relocation usually has no effect on a file that hasn't
	#   been relocated so the checksum check would likely succeed even
	#   though it really isn't ready to be used.
	#
	if {!$usingRsync} {
	    set tmppath [file join $temporaryTop $fromPath]
	    if {[file exists $tmppath]} {
		debugmsg "checking $tmppath for reuse, reloc translation $revreloc"
		if {[catch {openbreloc $tmppath $revreloc "r"} fd] != 0} {
		    debugmsg "error on openbreloc of $tmppath: $fd"
		} else {
		    alwaysEvalFor "" {catch {closebreloc $fd}} {
			if {[catch {compareMdDataFor $path $expectedMdData \
					[$mdType -chan $fd]} string] == 0} {
			    transfermsg "Using previously fetched $fromPath"
			    continue
			}
		    }
		    debugmsg "failed to reuse because $string"
		}
		file delete $tmppath
	    }
	}

	set perm $nupContents([list paths $path perm])
	if {[info exists nupContents([list paths $path group])]} {
	    # it's a security hole to create the temporary file setgid to
	    #   the wrong group
	    set perm [removeSetgidPerm $perm]
	}
	lappend pathsInfo \
	    [list $fromPath $temporaryTop $path $perm $expectedMdData $installTop $reloc]
    }
}

#
# When multiple installTops are being installed into in the same nsbd run,
#  this function copies the portable files from one installTop to another.
# Assuming all the files have been fetched into the temporaryTop directories,
#  make the rest of the temporary files needed for the update: if nupContents
#  is different from anotherNupContents, copy portable files from there.
# Also, clean up the temporary/internal variables in nupContents that will
#  no longer be needed.
#
proc copyPortableTemps {nupContentsName} {
    upvar $nupContentsName nupContents

    set installTop $nupContents(installTop)
    set temporaryTop $nupContents(temporaryTop)
    set mdType $nupContents(mdType)

    foreach path $nupContents(paths) {
	if {[isDirectory $path]} {
	    continue
	}
	if {[info exists nupContents([list paths $path linkTo])]} {
	    continue
	}
	if {[info exists nupContents([list paths $path hardLinkTo])]} {
	    continue
	}
	if {[info exists nupContents([list paths $path otherLoadPath])]} {
	    set loadPath $nupContents([list paths $path loadPath])
	    set toPath [file join $temporaryTop $loadPath]
	    notrace {withParentDir {
		if {[info exists nupContents([list paths $path otherRevreloc])]} {
		    progressmsg "Duplicating & relocating $loadPath"
		    set fd1 [openbreloc \
			$nupContents([list paths $path otherLoadPath]) \
			$nupContents([list paths $path otherRevreloc]) "r"]
		    alwaysEvalFor "" {closebreloc $fd1} {
			set perm $nupContents([list paths $path perm])
			if {[info exists nupContents([list paths $path group])]} {
			    # it's a security hole to create the temporary file
			    #   setgid to the wrong group
			    set perm [removeSetgidPerm $perm]
			}
			file delete -force $toPath
			set fd2 [openbreloc $toPath \
				    $nupContents(loadReloc) "w" $perm]
			alwaysEvalFor "" {closebreloc $fd2} {
			    fcopy $fd1 $fd2
			}
		    }
		    unset nupContents([list paths $path otherRevreloc])
		} else {
		    transfermsg "Duplicating $loadPath"
		    file copy -force \
			$nupContents([list paths $path otherLoadPath]) $toPath
		}
	    } $toPath}
	    unset nupContents([list paths $path otherLoadPath])
	} elseif {[info exists nupContents([list paths $path nonPortable])]} {
	    unset nupContents([list paths $path nonPortable])
	}
	unset nupContents([list paths $path length])
	unset nupContents([list paths $path $mdType])
	unset nupContents([list paths $path mode])
    }

    unset nupContents(loadReloc)
    unset nupContents(loadRevreloc)
    catch {unset nupContents(topUrl)}
    catch {unset nupContents(multigetUrl)}
}

#
# Return 1 if rsync should be used, otherwise 0.  contentsName is the
#   name of the array which holds the keywords
#
proc isRsyncFetch {contentsName} {
    upvar $contentsName contents
    global cfgContents
    if {[info exists contents(topUrl)] &&
	    [regexp -nocase "^rsync://" $contents(topUrl)] &&
		(![info exists contents(multigetUrl)] ||
		    [info exists cfgContents(rsync)])} {
	# topUrl starts with rsync, and there is either no multigetUrl or
	#   the user has explicitly set the rsync configuration keyword
	return 1
    }
    return 0
}

#
# If using rsync or if the multigetUrl keyword is available, get the
#   paths in pathsInfo together, otherwise get each one separately
#
proc multiFetchPaths {contentsName pathsInfo executableTypes versions} {
    global cfgContents
    upvar $contentsName contents
    set package $contents(package)

    if {$pathsInfo == ""} {
	return
    }
    set mdType $contents(mdType)

    if {[info exists contents(topUrl)]} {
	set urls [substituteUrl $contents(topUrl) \
		    $package $executableTypes $versions]
	if {[llength $urls] > 1} {
	    nsbderror "topUrl $contents(topUrl) substitutes to [llength $urls] values; must be only one"
	}
	set topUrl [lindex $urls 0]
	if {[isRsyncFetch contents]} {
	    urlRsyncMultiMdCopy $topUrl $mdType $pathsInfo
	    return
	}
    }

    if {[info exists contents(multigetUrl)]} {
	set urls [substituteUrl $contents(multigetUrl) \
		    $package $executableTypes $versions]
	if {[llength $urls] > 1} {
	    nsbderror "multigetUrl $contents(multigetUrl) substitutes to [llength $urls] values; must be only one"
	}
	urlMultiMdCopy [lindex $urls 0] $mdType $pathsInfo
	return
    }
    if {![info exists contents(topUrl)]} {
	nsbderror "topUrl and multigetUrl keyword both missing"
    }

    set endTop [expr [string length $topUrl] - 1]
    if {[string index $topUrl $endTop] == "/"} {
	# remove trailing slash
	set topUrl [string range $topUrl 0 [expr $endTop - 1]]
    }

    global cmdKeytable
    set topPath ""
    if {[info exists cmdKeytable(topUrl)]} {
	# if topUrl was set on the command line and the URL is of the
	#   the form file://, topPath will be set to the local file path
	# This is an undocumented feature because I can't figure out where
	#   it fits in the documentation; it certainly doesn't belong in
	#   the description of "topUrl" inside the '.nsb' or '.npd' files
	# This is useful for re-"distributing" a package from one place to
	#   another on the same machine.
	regexp {file://[^/]*(.+)} $topUrl x topPath
	if {$topPath != ""} {
	    progressmsg "Copy-from top $topPath"
	}
    }
    foreach pathInfo $pathsInfo {
	foreach {fromPath toTop finalPath mode expectedMdData xx reloc} $pathInfo {}
	set toPath [file join $toTop $fromPath]
	if {$topPath != ""} {
	    # read from local file
	    progressmsg "Copying $fromPath"
	    set filename [file join $topPath $fromPath]
	    withOpen fdFrom $filename "r" {
		fconfigure $fdFrom -translation binary
		set fdTo [withParentDir \
			    {openbreloc $toPath $reloc "w" $mode} $toPath]
		alwaysEvalFor "" {closebreloc $fdTo} {
		    set mdData [$mdType -copychan $fdTo -chan $fdFrom]
		}
	    }
	    compareMdDataFor $fromPath $expectedMdData $mdData
	} else {
	    urlMdCopy $topUrl $fromPath $mdType $expectedMdData $toPath $reloc $mode
	}
    }
}

#
# install all the paths listed in nupContents from the temporaryTop directory
#  to the installTop directory, and clean out the temporaryTop directory.
# NOTE: much of this logic is parallelled in previewNupPaths, so changes
#  that are made here might have to also be made there
#
proc installNupPaths {} {
    upvar nupContents nupContents
    global cfgContents procNsbType

    set temporaryTop $nupContents(temporaryTop)
    set installTop $nupContents(installTop)
    set package $nupContents(package)
    set createMask $cfgContents(createMask)
    # dirperm is the default permission used by mkdir
    set dirperm [format "0%o" [expr "0777" & ~$createMask]]

    set firstmsg "Install top $installTop"
    set removedPaths ""
    set preserveMtimes 0
    if {![info exists cfgContents(preserves)] || 
	[lsearch -exact $cfgContents(preserves) "mtimes"]} {
	set preserveMtimes 1
    }
    foreach path $nupContents(paths) {
	set toPath [file join $installTop $path]
	if {[info exists nupContents([list paths $path backupPath])]} {
	    if {[file exists $toPath]} {
		set bPath $nupContents([list paths $path backupPath])
		installNupUpdatemsg "Backing up $path to $bPath"
		set backupPath [file join $installTop $bPath]
		robustDelete $backupPath $temporaryTop
		notrace {withParentDir {file rename $toPath $backupPath}}
	    }
	}
	set group ""
	set groupmsg ""
	if {[info exists nupContents([list paths $path group])]} {
	    set group $nupContents([list paths $path group])
	    unset nupContents([list paths $path group])
	    set groupmsg " group $group"
	}
	if {[isDirectory $path]} {
	    set perm $nupContents([list paths $path perm])
	    unset nupContents([list paths $path perm])
	    if {[set toPathType [robustFileType $toPath]] != "directory"} {
		installNupUpdatemsg "Making directory $path mode $perm$groupmsg"
		if {$toPathType != ""} {
		    # wasn't missing and was not directory
		    robustDelete $toPath $temporaryTop
		}
		notrace {file mkdir $toPath}
		if {$group != ""} {
		    set perm [changeGroupPerm $toPath $group $perm]
		}
		if {$perm != $dirperm} {
		    changeMode $toPath $perm
		}
	    }
	} elseif {[info exists nupContents([list paths $path linkTo])]} {
	    set link [relativeLinkPath $nupContents([list paths $path linkTo]) $path]
	    installNupUpdatemsg "Linking $path to $link"
	    if {[set toPathType [robustFileType $toPath]] == "directory"} {
		# keep track of directories deleted so we don't try to
		#   remove files under it later
		lappend removedPaths "$path/*"
	    }
	    if {$toPathType != ""} {
		robustDelete $toPath $temporaryTop
	    }
	    notrace {withParentDir {symLink $link $toPath}}
	} elseif {[info exists nupContents([list paths $path hardLinkTo])]} {
	    set link $nupContents([list paths $path hardLinkTo])
	    installNupUpdatemsg "Hard-linking $path to $link"
	    set link [file join $installTop $link]
	    robustDelete $toPath $temporaryTop
	    notrace {withParentDir {hardLink $link $toPath}}
	} else {
	    set perm $nupContents([list paths $path perm])
	    unset nupContents([list paths $path perm])
	    installNupUpdatemsg "Installing $path mode $perm$groupmsg"
	    robustDelete $toPath $temporaryTop
	    set loadPath $nupContents([list paths $path loadPath])
	    notrace {withParentDir \
		{file rename [file join $temporaryTop $loadPath] $toPath}}
	    if {$group != ""} {
		set perm [changeGroupPerm $toPath $group $perm]
	    }
	    # can't assume anything about the permissions that a file was
	    #   created with because it may have been copied by rsync which
	    #   uses the original file permissions less umask bits
	    changeMode $toPath $perm

	    if {[info exists nupContents([list paths $path mtime])]} {
		if {$preserveMtimes} {
		    changeMtime $toPath $nupContents([list paths $path mtime])
		}
		unset nupContents([list paths $path mtime])
	    }
	}
	if {[info exists nupContents([list paths $path new])]} {
	    unset nupContents([list paths $path new])
	}
    }

    debugmsg "Cleaning temporary top $temporaryTop"
    catch {file delete -force $temporaryTop}
    # remove it's parent too if it is empty (Do *NOT* use -force)
    catch {file delete [file dirname $temporaryTop]}

    unset nupContents(temporaryTop)
    foreach path $nupContents(removePaths) {
	set skip 0
	foreach removedPath $removedPaths {
	    if {[string match $removedPath $path]} {
		debugmsg "skipping remove of $path because matched $removedPath"
		set skip 1
		break
	    }
	}
	if {$skip} {
	    continue
	}
	set toPath [file join $installTop $path]
	if {[isDirectory $path]} {
	    # Do *NOT* use -force!!  Fail silently if the directory
	    #  is not empty
	    if {[robustFileType $toPath] == "directory"} {
		installNupUpdatemsg "Deleting $path if empty"
		catch {file delete $toPath}
	    }
	} else {
	    # silently skip deleting a file if its parent directory has been
	    #   deleted or it has turned into a directory
	    if {[file isdirectory [file dirname $toPath]] &&
		    ([robustFileType $toPath] != "directory")} {
		installNupUpdatemsg "Deleting $path"
		robustDelete $toPath $temporaryTop
	    }
	}
    }
    if {($firstmsg != "") && ($procNsbType != "remove")} {
	updatemsg "No updates to files in package for install top $installTop"
    }
}

proc installNupUpdatemsg {msg} {
    uplevel {
	if {$firstmsg != ""} {
	    updatemsg $firstmsg
	    set firstmsg ""
	}
    }
    updatemsg $msg
}

#
# if changeGroup fails print warning and remove a setgid bit from permission
#
proc changeGroupPerm {path group perm} {
    if {[catch {changeGroup $path $group} msg] != 0} {
	warnmsg "Warning: $msg"
	set perm [removeSetgidPerm $perm]
    }
    return $perm
}

#
# Execute any updateCommands, passing an extra parameter of the name of
#  an nsbdUpdate file
#
proc executeUpdateCommands {package commandsName contentsName {ignoreErrors 0}} {
    upvar $contentsName contents
    global cfgContents
    set singularName [string range $commandsName 0 \
			[expr [string length $commandsName] - 2]]
    set commands [nrdLookup $package $commandsName]
    if {[info exists cfgContents($commandsName)]} {
	set commands [concat $commands $cfgContents($commandsName)]
    }
    if {$commands == ""} {
	return
    }
    set scratchUpdName [scratchAddName "nup"]
    nsbdGenFile $scratchUpdName nup contents

    foreach command $commands {
	# use alwaysEvalFor just to add the command name to error messages
	alwaysEvalFor $command {} {
	    set dontprocess 0
	    if {[string index $command 0] == "@"} {
		set dontprocess 1
		set command [string range $command 1 end]
	    }
	    set command "$command $scratchUpdName"
	    progressmsg "Executing $singularName:\n  $command"
	    if {$dontprocess} {
		set code [catch {popen $command "w"} result]
	    } else {
		set code [catch {popen $command "r"} result]
	    }
	    if {$code > 0} {
		if {$ignoreErrors} {
		    updatemsg "error executing command, ignoring:\n  $result"
		} else {
		    nsbderror "$result"
		}
	    } else {
		set fd $result
		if {!$dontprocess} {
		    set firstline 1
		    set code [catch {
			    while {[gets $fd line] >= 0} {
				if {$firstline} {
				    updatemsg "command returned the following:\n  "
				    updatemsg "$line"
				    set firstline 0
				} else {
				    updatemsg "$line"
				}
			    }
			} result]
		}
		if {$code > 0} {
		    # already have an error, ignore another error from close
		    catch {close $fd}
		} else {
		    # also look for an error in close
		    set code [catch {close $fd} result]
		}
		if {$code > 0} {
		    if {$ignoreErrors} {
			updatemsg "error from command, ignoring:\n  $result"
		    } else {
			nsbderror "$result"
		    }
		}
	    }
	}
    }
    scratchClean $scratchUpdName
}

# ------------------------------------------------------------------
# functions used for nsbd -register and the GUI interface
# ------------------------------------------------------------------

#
# prompt for any unmet requiredPackages requirements
# Return 1 if registration can proceed.
# Return 0 if need to abort processing of registration.
#
proc promptUnmetRequirements {registerPackage executableTypes} {
    set unmet [unmetRequirementPackages $executableTypes]
    if {$unmet == ""} {
	return 1
    }
    set updateList ""
    set updateMsg ""
    set registerList ""
    set registerMsg ""
    set unavailableList ""
    set unavailableMsg ""
    foreach {package requirement nsbUrl} $unmet {
	if {$requirement == "not registered"} {
	    if {$nsbUrl == ""} {
		lappend unavailableList $package
	    } else {
		lappend registerList $package $nsbUrl
	    }
	} else {
	    lappend updateList $package $requirement
	}
    }
    if {$updateList != ""} {
	if {[llength $updateList] > 2} {
	    set thisPackage "these packages"
	    set msg "Warning: $thisPackage do not meet requirements:"
	    foreach {package requirement} $updateList {
		append msg "\n  $package $requirement"
	    }
	} else {
	    set package [lindex $updateList 0]
	    set thisPackage "package $package"
	    set msg "Warning: $thisPackage does not meet requirements."
	}
	append msg "\nDo you want to check for updates to $thisPackage"
	append msg "\n  instead of registeringing $registerPackage at this time?"
	set answer [tk_dialog .d "" $msg warning 0 \
	    "Check $thisPackage" "Skip check, proceed" "Cancel registration"]
	if {$answer == 2} {
	    return 0
	}
	if {$answer == 0} {
	    foreach {package requirement} $updateList {
		option-update [list $package]
	    }
	    tk_dialog .d "" "Update check complete" "" 0 "Exit"
	    return 0
	}
    }
    if {$registerList != ""} {
	if {[llength $registerList] > 2} {
	    set thisPackage "these packages"
	    set msg "Warning: these required packages are not registered:"
	    foreach {package nsbUrl} $registerList {
		append msg "\n  $package"
	    }
	} else {
	    set package [lindex $registerList 0]
	    set thisPackage "package $package"
	    set msg "Warning: required $thisPackage is not registered."
	}
	append msg "\nDo you want to register $thisPackage instead of"
	append msg "\n  registering $registerPackage at this time?"
	set answer [tk_dialog .d "" $msg warning 0 "Register $thisPackage" \
		"Skip $thisPackage, proceed" "Cancel registrations"]
	if {$answer == 2} {
	    return 0
	}
	if {$answer == 0} {
	    foreach {package nsbUrl} $registerList {
		procfile $nsbUrl nsb
	    }
	    return 0
	}
    }
    if {$unavailableList != ""} {
	if {[llength $unavailableList] > 1} {
	    set thisPackage "these packages"
	    set msg "Warning: these required packages are not registered:"
	    foreach package $unavailableList {
		append msg "\n  $package"
	    }
	} else {
	    set package [lindex $unavailableList 0]
	    set thisPackage "package $package"
	    set msg "Warning: required $thisPackage is not registered."
	}
	append msg "\nNo information was provided about how to register"
	append msg "\n  for $thisPackage."
	append msg "\nDo you want to proceed with registering $registerPackage anyway?"
	set answer [tk_dialog .d "" $msg warning 0 \
			"Proceed with registration" "Cancel registration"]
	if {$answer == 1} {
	    return 0
	}
    }
    return 1
}

#
# prompt to register the package described in nsbContents
#

set promptKeys {
    nsbUrl maintainers minPollPeriod executableTypes installTop relocTop
    nsbStorePath pathSubs regSubs validPaths 
    preUpdateCommands postUpdateCommands
}

proc promptToRegister {package executableTypes versions} {
    if {[nrdPackageRegistered $package]} {
	set answer [tk_dialog .d "" \
"The $package package is already registered.
  Do you want to overwrite it?" warning 0 "Proceed" "Cancel"]
	if {$answer == 1} {
	    return
	}
    }
	
    global nsbContents promptKeys promptValueScripts

    catch {unset promptValueScripts}

    set w ".register"
    toplevel $w
    wm withdraw $w
    wm title $w "NSBD registration of package $package"
    label $w.disclaimer -text \
{This is the Not-So-Bad Distribution (NSBD) package registration window.
IMPORTANT NOTE: a digital signature on a package only authenticates that the
package comes from the person who signed it.  It makes no guarantees on the
integrity of the person or package.  Register for packages at your own risk.    }
    pack $w.disclaimer
    global warnUpdateCommands
    set warnUpdateCommands 0
    foreach key $promptKeys {
	set numlines 1
	set commalist 0
	set defaultValue ""
	if {[info exists nsbContents($key)]} {
	    set value $nsbContents($key)
	} else {
	    set value [nrdLookup $package $key]
	}
	switch $key {
	    nsbUrl {
		set label "URL of '.nsb' file:  "
	    }
	    maintainers {
		set label "PGP ids of maintainers:  "
		set numlines 2
	    }
	    minPollPeriod {
		set label "Minimum poll period:  "
		if {$value == ""} {
		    set value "1d"
		    set defaultValue $value
		}
	    }
	    executableTypes {
		if {$value == ""} {
		    continue
		}
		set label "Executable types:  "
		set numlines [llength $executableTypes]
		if {$numlines < 2} {
		    set numlines 2
		} elseif {$numlines > 5} {
		    set numlines 5
		}
		set value $executableTypes
	    }
	    installTop {
		set label "Install directory:    "
		if {$value == ""} {
		    set value [unsubstitutedInstallTop $package]
		    set defaultValue $value
		}
	    }
	    relocTop {
		if {![info exists nsbContents(installTop)]} {
		    # no need to prompt for this if there was no installTop
		    #  specified by the maintainer
		    continue
		}
		set label "Relocation top:    "
	    }
	    nsbStorePath {
		set label "Path to store '.nsb' file: "
		if {$value == ""} {
		    set value [defaultNsbStorePath]
		    set defaultValue $value
		}
	    }
	    pathSubs {
		set label "User path substitutions:    "
		set numlines 2
		# don't use nsbContents for this one
		set value [nrdLookup $package $key]
	    }
	    regSubs {
		set label "User regexp substitutions: "
		set numlines 2
		# don't use nsbContents for this one
		set value [nrdLookup $package $key]
	    }
	    validPaths {
		set label "Valid paths:          "
		set numlines 5
		# make default be calculated validPaths, taking priority
		#  over any previous validPaths in the nrd
		substitutePaths $package nsbContents subContents \
					    $executableTypes $versions 1
		set value [calculateValidPaths subContents]
	    }
	    preUpdateCommands {
		if {$value != ""} {
		    set warnUpdateCommands 1
		}
		set label "Pre-update commands:   "
		set numlines 2
	    }
	    postUpdateCommands {
		if {$value != ""} {
		    set warnUpdateCommands 1
		}
		set label "Post-update commands: "
		set numlines 2
	    }
	}
	frame $w.${key}Frame
	pack $w.${key}Frame -fill x -padx 10 -pady 2
	set trimmedLabel [string trimright $label]
	button $w.${key}Label -text "$trimmedLabel" \
			-command "registryHelp $key" -takefocus 0
	pack $w.${key}Label -in $w.${key}Frame -side left
	set fill [string range $label [string length $trimmedLabel] end]
	label $w.${key}Fill -text "$fill" 
	pack $w.${key}Fill -in $w.${key}Frame -side left
	if {$numlines == 1} {
	    entry $w.$key -width 60
	    if {$commalist} {
		$w.$key insert end [join $value ","]
		set script "set data \[$w.$key get\]"
		append script {
		    regsub -all {[ \t]} $data "" data
		    split $data ","
		}
	    } else {
		$w.$key insert end $value
		set script "set v \[string trim \[$w.$key get\]\]"
		if {$defaultValue != ""} {
		    append script "\nexpr {\$v == \"$defaultValue\" ? \"\" : \$v}"
		}
	    }
	    pack $w.$key -in $w.${key}Frame -side left -expand 1 -fill x
	    bind $w.$key <Return> "event generate $w.$key <Tab>"
	} else {
	    text $w.$key -width 60 -height $numlines -wrap none \
			    -yscrollcommand "$w.${key}Scroll set"
	    scrollbar $w.${key}Scroll -command "$w.$key yview" -takefocus 0
	    $w.$key insert end [join $value "\n"]
	    pack $w.${key}Scroll -in $w.${key}Frame -side right -fill y
	    pack $w.$key -in $w.${key}Frame -side left -fill x -expand 1
#	    bind $w.$key <FocusIn> {
#		# This isn't exactly the same behavior as in an Entry,
#		#  but it is close enough
#		if {[%W compare insert == "end - 1 chars"]} {
#		    %W tag add sel 0.0 end
#		}
#	    }
	    set script "set data \[$w.$key get 0.0 end\]"
	    append script {
		set trimmedData ""
		foreach datum [split $data "\n"] {
		    set datum [string trim $datum]
		    if {$datum != ""} {
			lappend trimmedData $datum
		    }
		}
		set trimmedData
	    }
	}
	set promptValueScripts($key) $script
    }
    if {$warnUpdateCommands} {
	global updateCommandsApproved
	set updateCommandsApproved 0
	label $w.warnCommandsLabel -text \
{Pre or Post update commands were provided, which can be particularly dangerous.}
	pack $w.warnCommandsLabel
	checkbutton $w.warnCommandsButton -variable updateCommandsApproved -text \
{Check here to indicate that you have approved the update commands.}
	pack $w.warnCommandsButton
    }
    frame $w.line -bd 2 -height 4 -relief raised
    pack $w.line -fill x -padx 5
    frame $w.buttons
    pack $w.buttons -fill x
#   frame $w.buttons.default -relief sunken -bd 1
#   pack $w.buttons.default -side left -expand 1 -pady 4
#   frame $w.buttons.default.frame -relief raised -bd 1
#   pack $w.buttons.default.frame -padx 2 -pady 2
    button $w.attempt -text "Install and register" -command {installRegister}
    button $w.cancel -text "Cancel registration" -command "destroy $w"
    button $w.help -text "Help" -command {registryHelp overall}
#   pack $w.attempt -in $w.buttons.default.frame -padx 2 -pady 2
    pack $w.attempt -in $w.buttons -side left -expand 1 -pady 4
    pack $w.cancel -in $w.buttons -side left -expand 1 -pady 4
    pack $w.help -in $w.buttons -side left -expand 1 -pady 4
    foreach button "$w.attempt $w.cancel $w.help" {
	bind $button <Return> [$button cget -command]
    }
    tkCenter $w

    focus $w.nsbUrl
#    $w.nsbUrl selection range 0 end
#    $w.nsbUrl icursor end

    tkwait window $w
}

#
# Attempt installation of the package and register if successful
#
proc installRegister {} {
    set w ".register"
    global warnUpdateCommands updateCommandsApproved
    if {$warnUpdateCommands && !$updateCommandsApproved} {
	tk_dialog $w.d "" \
"You must check the box to approve
update commands before proceeding" warning 0 "Cancel"
	return
    }
    global ignoreSecurity cfgContents nsbContents promptKeys promptValueScripts
    set package $nsbContents(package)
    if {!$ignoreSecurity && ![info exists cfgContents(pgp)]} {
	set answer [tk_dialog $w.d "" \
"The 'pgp' configuration keyword is not set and the
  '-ignoreSecurity' command line option was not used.
  Do you want to proceed and ignore security?" \
				warning 0 "Proceed" "Cancel install"]
	if {$answer == 1} {
	    destroy $w
	    return
	}
	set ignoreSecurity 1
    }
    if {!$ignoreSecurity} {
	foreach id [eval $promptValueScripts(maintainers)] {
	    if {![pgpIDKnown $id]} {
		set keylist [list maintainers $id pgpKeyUrl]
		if {[info exists nsbContents($keylist)]} {
		    set answer [tk_dialog $w.d "" \
"The PGP public key of maintainer
    $id
is not known to PGP, but a URL for the key has
been supplied.  Do you want to register the key?" \
			    "" 0 "Register the key" "Cancel install"]
		    if {$answer == 1} {
			destroy $w
			return
		    }
		    set scratch [scratchAddName "key"]
		    urlCopy $nsbContents($keylist) $scratch "" \
				"-progress urlProgress"
		    pgpAddKey $id $scratch
		    scratchClean $scratch
		} else {
		    nsbderror \
"The PGP public key of maintainer
    $id
is not registered and no pgpKeyUrl was supplied."
		}
	    }
	}
    }
    foreach key $promptKeys {
	if {[info exists promptValueScripts($key)]} {
	    nrdUpdate $package "set" $key [eval $promptValueScripts($key)]
	}
    }
    raiseMessagesWindow
    global procNsbType
    set procNsbType "register-update"
    set code [catch {procnsbpackages [list $package]} err]
    if {$code > 0} {
	global errorCode errorInfo
	set msg "Error: $err"
	set savErrorInfo $errorInfo
	set savErrorCode $errorCode
	set ans [tk_dialog .tkerror "Error in NSBD update" $msg error 0 \
				    "Exit" "Escalate for trace" "Try Again"]
	if {$ans == 0} {
	    nsbdExit 1
	}
	if {$ans == 1} {
	    error $err $errorInfo $errorCode
	}
	hideMessagesWindow
	return
    }
    tk_dialog $w.d "" "Installation and registration\n  of $package complete" "" 0 "Exit"
    destroy $w
}

#
# Pop up a help window with info about the registry key $key
#
proc registryHelp {key} {
    if {$key == "overall"} {
	set msg \
"This is [nsbdVersion].
This window is for registering an NSBD-compliant package.

When you press 'Install and register', an attempt will
  be made to install the package.  If there are any errors
  in the installation, the registration will be backed out;
  if there are no errors, the package will be registered.
  You can later check for updates through command line
  options and won't need this window.

For help on individual registration items, click on the
  label for the item."
    } else {
	global nrdKeylist
	foreach {c k v} $nrdKeylist {
	    if {$k == "packages $key"} {
		set msg [join $c "\n"]
		break
	    }
	}
	if {$msg == ""} {
	    nsbderror "Internal error - cannot find comment for nrd key $key"
	}
    }
    tk_dialog .helpd "NSBD Help" $msg info 0 "Ok"
}
