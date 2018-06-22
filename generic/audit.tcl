#
# Functions to implement the NSBD audits.  Audits are generally done in
#  two passes: the first pass, driven by "auditpackage", compares the
#  saved '.nsb' files with the files that are installed.   The second
#  pass, driven by "auditextras", looks through all the files under 
#  directories under installed packages to see if there are extra files.
# Depending on the auditOptions, audits can either repair or just report
#  problems.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 28 April 1999
#
#
# Copyright (C) 1999-2003 by Dave Dykstra and Lucent Technologies
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
# Define audit error codes and their corresponding error messages
#
array set auditmsgs {
    missing		"does not exist"
    wronglength		"does not have expected length"
    badchecksum		"does not have expected checksum"
    notdirectory	"is not a directory"
    badgroup		"does not have expected group"
    badperm		"does not have expected permissions"
    notsymlinkedto	"is not symbolic-linked to"
    nothardlinkedto	"is not hard-linked to"
    notfile		"is not a file"
    unopenable		"cannot be opened"
    notauthorized	"not signed by an authorized maintainer"
    unrecognizedkey	"signed by an unrecognized key"
    badsignature	"has a bad signature"
    pgperror		"cannot be verified because of pgp error"
}

#
# Drive the audit
#
proc auditpackages {packagelist} {
    global auditTotalErrors
    set auditTotalErrors 0

    auditinit $packagelist

    applyCmdkeys cmdContents nsb

    set packagelist [expandRegisteredPackages $packagelist "-audit"]
    foreach package $packagelist {
	auditpackage $package cmdContents
    }

    global auditextra
    if {$auditextra} {
	auditextras $packagelist cmdContents
    }

    updatemsg "Audit completed with $auditTotalErrors errors"
}

#
# Initialize audit options variables.  A boolean global "audit$name" is
#  for each option name.
#
proc auditinit {packagelist} {
    global auditall auditdeletepercent
    set auditall [expr {$packagelist == "all"}]

    global cfgContents

    if {[info exists cfgContents(auditOptions)]} {
	set auditOptions $cfgContents(auditOptions)
    } else {
	set auditOptions ""
    }
    set knownOptions "checksig checksums extra delete repair update"
    proc regOpt {opt} {
	if {$opt == "delete"} { return "^delete(%.*|)$" } 
	return "^$opt$"
    }
    foreach option $auditOptions {
	set gotit 0
	foreach knownOption $knownOptions {
	    if {[regexp [regOpt $knownOption] $option]} {
		set gotit 1
		break
	    }
	}
	if {!$gotit} {
	    warnmsg "warning: unknown auditOption $option ignored"
	}
    }
    set auditdeletepercent ""
    foreach name $knownOptions {
	set varname audit$name
	global $varname
	if {[set optidx [lsearch -regexp $auditOptions [regOpt $name]]] >= 0} {
	    set option [lindex $auditOptions $optidx]
	    set $varname 1
	    switch $name {
		"delete" {
		    set auditextra 1
		    regexp "^delete(%(.*)|)$" $option x x auditdeletepercent
		    if {$auditdeletepercent == ""} {
			set auditdeletepercent "10"
		    }
		    if {($auditdeletepercent <= 0) ||
						($auditdeletepercent > 100)} {
			nsbderror "auditOptions delete% must be in the range of 1 to 100"
		    }
		}
		"update" {
		    set auditrepair 1
		}
	    }
	} else {
	    set $varname 0
	}
    }
}

#
# Start the audit for a particular package and installTop
#
proc auditstart {installTop {package ""}} {
    global auditPackage auditTop auditErrors
    set auditPackage $package 
    set auditTop $installTop
    set auditErrors 0
    if {$package == ""} {
	progressmsg "Auditing for extras under installTop $installTop"
    } else {
	progressmsg "Auditing package $package for installTop $installTop"
    }
}

#
# Display an audit error message
#
proc auditmsg {msg} {
    global auditTotalErrors auditErrors
    incr auditTotalErrors
    if {[incr auditErrors] == 1} {
	global auditPackage auditTop
	if {$auditPackage == ""} {
	    updatemsg "Audit errors for installTop $auditTop"
	} else {
	    updatemsg "Audit errors in package $auditPackage for installTop $auditTop"
	}
    }
    updatemsg $msg
}

#
# Look up the message for an error code and display it.
# This function could be eliminated and just have the messages be inline
#
proc auditerror {fname code args} {
    global auditmsgs
    set msg "$fname $auditmsgs($code)"
    if {$args != ""} {
	append msg " [join $args " "]"
    }
    auditmsg $msg
}

#
# Log when a file checked out ok
#
proc auditok {fname type args} {
    set msg "$fname $type OK"
    if {$args != ""} {
	append msg " [join $args " "]"
    }
    transfermsg $msg
}

#
# Audit a package, matching stored '.nsb' files against what is existing.
#   Also handle the auditOptions checksig, checksums, repair, and update,
#   and prepare for the extra & delete options.
#
proc auditpackage {package cmdContentsname} {
    upvar $cmdContentsname cmdContents
    initPathPerms $package
    initPathGroups $package

    set executableTypes [getExecutableTypes $package cmdContents 1]
    set versions [getVersions $package cmdContents]

    #
    # As a side effect this function sets four arrays: topNsbStoreNames and
    #   topRelocParams are indexed by the installTops, and storeExecutableTypes
    #   and storeVersions are indexed by the topNsbStoreNames
    #
    set installTops [calculateInstallTops $package $executableTypes $versions]

    global auditchecksig auditchecksums auditextra auditrepair auditupdate
    foreach installTop $installTops {
	auditstart $installTop $package

	set relocParams $topRelocParams($installTop)
	set relocTop [lindex $relocParams 0]

	foreach nsbStoreName $topNsbStoreNames($installTop) {

	    if {$auditchecksig} {
		auditsignature $package $nsbStoreName $installTop
	    }

	    loadOldNsbFile 1 $nsbStoreName $package \
	      $storeExecutableTypes($nsbStoreName) $storeVersions($nsbStoreName)
	    upvar 0 oldnsbContents nsbContents
	    upvar 0 oldnupContents nupContents

	    if {![info exists nupContents(paths)]} {
		if {!$auditupdate} {
		    clearOldNsbFile 1
		}
		continue
	    }
	    set mdType $nupContents(mdType)
	    set reloadPaths ""
	    if {$auditrepair} {
		set temporaryTop [getTemporaryTop $installTop $package]
	    }

	    set reloc ""
	    if {$relocTop != ""} {
		# the origInstalTop can't be determined until after the
		#  .nsb file is loaded
		set origInstallTop [eval \
		    "getOrigInstallTop [lindex $relocParams 1]"]
		if {($origInstallTop != "") && ($origInstallTop != $relocTop)} {
		    set reloc "$relocTop=$origInstallTop"
		}
	    }

	    foreach path $nupContents(paths) {
		set code [catch {
		    set fname [file join $installTop $path]
		    if {[catch {file lstat $fname statb} string] != 0} {
			debugmsg "lstat error $string"
			auditerror $path missing
			lappend reloadPaths $path
			continue
		    }
		    if {[isDirectory $path]} {
			if {$statb(type) != "directory"} {
			    auditerror $path notdirectory
			    lappend reloadPaths $path
			    continue
			}
			set mode "rwx"
			if {[auditgroupandperm]} {
			    auditok $path directory
			}
			continue
		    }
		    if {[info exists nupContents([list paths $path linkTo])]} {
			set link [relativeLinkPath $nupContents([list paths $path linkTo]) $path]
			if {($statb(type) != "link") || 
					([file readlink $fname] != $link)} {
			    if {$auditrepair} {
				auditmsg "Linking $path to $link"
				robustDelete $fname $temporaryTop
				notrace {withParentDir {symLink $link $fname}}
			    } else {
				auditerror $path notsymlinkedto $link
			    }
			    continue
			}
			auditok $path symlinked "to $link"
			continue
		    }
		    if {[info exists nupContents([list paths $path hardLinkTo])]} {
			set link $nupContents([list paths $path hardLinkTo])
			set flink [file join $installTop $link]
			if {[catch {file lstat $flink statb2} string] != 0} {
			    debugmsg "lstat error $string"
			    auditerror $path nothardlinkedto $link
			    lappend reloadPaths $path
			    continue
			}
			if {$statb(ino) != $statb2(ino)} {
			    if {$auditrepair} {
				auditmsg "Hard-linking $path to $link"
				robustDelete $fname $temporaryTop
				notrace {withParentDir {hardLink $flink $fname}}
			    } else {
				auditerror $path nothardlinkedto $link
			    }
			    continue
			}
			auditok $path hardlinked "to $link"
			continue
		    }
		    if {$statb(type) != "file"} {
			auditerror $path notfile
			lappend reloadPaths $path
			continue
		    }
		    set length $nupContents([list paths $path length])
		    if {$statb(size) != $length} {
			auditerror $path wronglength $length
			lappend reloadPaths $path
			continue
		    }
		    if {$auditchecksums} {
			if {[catch {openbreloc $fname $reloc "r"} fd] != 0} {
			    debugmsg "open error $fd"
			    auditerror $path unopenable
			    lappend reloadPaths $path
			    continue
			}
			alwaysEvalFor "" {closebreloc $fd} {
			    fconfigure $fd -translation binary
			    set mdData [$mdType -chan $fd]
			}
			set checksum $nupContents([list paths $path $mdType])
			if {[lindex $mdData 1] != $checksum} {
			    auditerror $path badchecksum
			    lappend reloadPaths $path
			    continue
			}
		    }
		    set mode $nupContents([list paths $path mode])
		    if {[auditgroupandperm]} {
			auditok $path file
		    }
		} emsg]

		if {$code == 1} {
		    auditmsg "error during audit, continuing: $emsg"
		}
	    }

	    if {$auditupdate && ($reloadPaths != "")} {
		# update the package after removing all the reload paths
		#   from the oldnupContents
		#
		set newpaths ""
		foreach path $nupContents(paths) {
		    if {[lsearch -exact $reloadPaths $path] >= 0} {
			foreach k "loadPath linkTo hardLinkTo length $mdType mode" {
			    catch {unset nupContents([list paths $path $k])}
			}
		    } else {
			lappend newpaths $path
		    }
		}
		set nupContents(paths) $newpaths

		# 
		# Update package using the current executableTypes & versions
		#
		
		global procNsbType
		set procNsbType "audit-update"
		procnsbpackages [list $package]

		if {$auditextra} {
		    # reload the old nsb file again now that we've done an
		    #  update, to make sure to notice any new files that were
		    #  just installed
		    clearOldNsbFile 1
		    loadOldNsbFile 1 $nsbStoreName $package \
				$storeExecutableTypes($nsbStoreName) \
				$storeVersions($nsbStoreName)
		    upvar 0 oldnupContents nupContents
		}
	    }

	    if {$auditextra} {
		#
		# Note the known paths under this installTop so
		#   unwanted paths can be located later
		#
		upvar knownPaths_$installTop knownPaths
		upvar knownInstallTops knownInstallTops
		luniqueAppend knownInstallTops $installTop
	    
		#
		# If the nsbStoreName is under installTop, note it
		#
		set len [string length $installTop]
		if {[string range $nsbStoreName 0 [expr {$len - 1}]] == 									$installTop} {
		    setknownPath $package \
			[string range $nsbStoreName $len end]
		}

		foreach path $nupContents(paths) {
		    setknownPath $package $path
		    # add backup paths too if present
		    #
		    if {[info exists nupContents([list paths $path backupPath])]} {
			setknownPath $package \
				$nupContents([list paths $path backupPath])
		    }
		}
	    }

	    # Not going to need old*Contents anymore, clear them out to
	    #   save memory.  May possibly be able to use them if doing an
	    #   update and this package's validPaths clash with those of
	    #   another package, but that situation is rare and then this
	    #   will just get reloaded.
	    clearOldNsbFile 1
	}
    }
}

#
# set knownPaths for path and any parent dir
#
proc setknownPath {package path} {
    upvar knownPaths knownPaths
    if {[info exists knownPaths($path)] && ![isDirectory $path]} {
	# nothing can be done to repair this, just report it
	auditmsg "$path duplicate with package $knownPaths($path)"
    }
    set knownPaths($path) $package
    while {([set path "[file dirname $path]/"] != ".") && 
		![info exists knownPaths($path)]} {
	set knownPaths($path) ""
    }
}

#
# audit the group and the permissions of $path against stat information
#   in statb.  This is in a procedure because it invoked from separate places
#   for directories and files.
#
proc auditgroupandperm {} {
    uplevel {
	set ok 1
	set group [getPathGroup $path]
	if {$group != ""} {
	    set gid [getGroupIdFromName $group]
	    if {$gid != $statb(gid)} {
		if {$auditrepair} {
		    set oldgroup [getGroupNameFromId $statb(gid)]
		    auditmsg "Changing $path from group $oldgroup to $group"
		    changeGroup $fname $group
		} else {
		    auditerror $path badgroup $group
		}
		set ok 0
	    }
	}
	set perm [getPathPerm $path $mode]
	set oldperm [expr {$statb(mode) & 07777}]
	if {$oldperm != $perm} {
	    if {$auditrepair} {
		auditmsg "Changing $path from mode [format 0%o $oldperm] to $perm"
		changeMode $fname $perm
	    } else {
		auditerror $path badperm $perm
	    }
	    set ok 0
	}
	return $ok
    }
}
#
# Check the signature on a stored '.nsb' file
#
proc auditsignature {package nsbStoreName installTop} {
    if {![file exists $nsbStoreName]} {
	return
    }
    set len [string length $installTop]
    if {[string range $nsbStoreName 0 [expr {$len - 1}]] == $installTop} {
	set relStoreName [string range $nsbStoreName $len end]
    } else {
	set relStoreName $nsbStoreName
    }
    # check the PGP signature
    set ans [pgpCheckFile $nsbStoreName]
    foreach {variant goodsig ids warning} $ans {}
    if {$goodsig} {
	set matchid ""
	set maintainers [nrdLookup $package maintainers]
	foreach id $ids {
	    if {[lsearch -exact $maintainers $id] >= 0} {
		set matchid $id
		break
	    }
	}
	if {$matchid == ""} {
	    auditerror $relStoreName notauthorized
	    debugmsg "authorized maintainers are $maintainers"
	    debugmsg "returned ids were $ids"
	}
	if {$warning != ""} {
	    warnmsg "Warning from $variant for $package:\n  WARNING: $warning\n"
	}
	auditok $relStoreName signature
    } else {
	# !goodsig
	if {$ids == "*UNKNOWN*"} {
	    auditerror $relStoreName unrecognizedkey
	}
	if {$ids != ""} {
	    auditerror $relStoreName badsignature
	}
	auditerror $relStoreName pgperror
	debugmsg "warning from $variant was $warning"
    }
}

#
# Locate extra files, deleting them if requested
#
proc auditextras {packagelist cmdContentsname} {
    upvar $cmdContentsname cmdContents
    global auditall auditdelete auditdeletepercent
    upvar knownInstallTops knownInstallTops

    if {![info exists knownInstallTops]} {
	return
    }
    if {$auditall} {
	foreach installTop $knownInstallTops {
	    set auditDirs_$installTop [list ""]
	}
    } else {
	foreach package $packagelist {
	    progressmsg "Preparing package $package for audit of extra files"
	    set executableTypes [getExecutableTypes $package cmdContents 1]
	    set versions [getVersions $package cmdContents]

	    #
	    # Make sure all packages with overlapping validPaths are included
	    #
	    set paths [nrdLookup $package validPaths]
	    set otherPackages [findOverlappingPackages $package $paths]
	    foreach otherPackage $otherPackages {
		if {([lsearch -exact $packagelist $otherPackage] < 0) &&
			([findNsbStoreFiles $otherPackage $executableTypes] != "")} {
		    nsbderror "cannot audit extra in $package because $otherPackage has conflicting validPaths"
		}
	    }

	    #
	    # Find out which installTops this package applies to
	    #
	    set installTops [calculateInstallTops $package \
					$executableTypes $versions]

	    #
	    # Add the directories in the validPaths to each installTop
	    #
	    set regwildcards {(\[)|(\])|([*?])}
	    foreach installTop $installTops {
		# use glob here to expand tildes
		set relStart [string length "[glob $installTop]/"]

		foreach path $paths {
		    if {![isDirectory $path] && ![regexp $regwildcards $path]} {
			# not a directory and don't have any wildcards
			continue
		    }

		    # path may be a wildcard, expand it
		    # glob will also remove non-existing directories
		    foreach dir [robustGlob $installTop$path] {
			if {[file type $dir] != "directory"} {
			    continue
			}
			set relDir [string range $dir $relStart end]
			if {![isDirectory $relDir]} {
			    append relDir "/"
			}
			lappend auditDirs_$installTop $relDir
		    }
		}
	    }
	}

	#
	# Remove any duplicates or subdirectories
	#
	foreach installTop $knownInstallTops {
	    set auditDirs_$installTop [collapsePaths [set auditDirs_$installTop]]
	}
    }

    #
    # Set up for determining when a path is deleted by pathSubs or regSubs
    #    in the config file
    #
    initPathSubstitutions "" bogusContents "" ""

    #
    # Look for extra paths under each installTop
    #
    foreach installTop $knownInstallTops {
	auditstart $installTop
	# use glob here to expand tildes
	set expandedInstallTop "[glob $installTop]/"
	set relStart [string length $expandedInstallTop]
	upvar knownPaths_$installTop knownPaths
	set totalfiles 0
	set deleteFiles ""
	foreach dir [set auditDirs_$installTop] {
	    incr totalfiles [auditextradir $expandedInstallTop$dir $relStart]
	}
	if {$auditdelete} {
	    set numdeletes [expr {[llength $deleteFiles] / 2}]
	    if {$numdeletes > ($totalfiles * $auditdeletepercent / 100)} {
		auditmsg "Skipping deletes because $numdeletes is more than ${auditdeletepercent}% of $totalfiles"
		continue
	    }
	    set temporaryTop [file join [getInstallTmp $installTop] .auditclean]
	    addToScratchFiles $temporaryTop
	    foreach {relname fname} $deleteFiles {
		if {[isDirectory $relname]} {
		    updatemsg "Deleting $relname if empty"
		    # Do *NOT* use -force!!  Fail silently if the directory
		    #  is not empty
		    catch {file delete $fname}
		} else {
		    updatemsg "Deleting $relname"
		    if {[catch {robustDelete $fname $temporaryTop} emsg] == 1} {
			auditmsg "$emsg, continuing"
		    }
		}
	    }
	}
    }
}

#
# Audit given directory relative for extra files.  relStart is the index
#   of the relative portion of the directory path.
# Return the total number of files found.
#
proc auditextradir {dir relStart {expand 0}} {
    global auditdelete
    upvar knownPaths knownPaths
    upvar PathSubstitutions PathSubstitutions
    upvar BackupSubstitutions BackupSubstitutions
    if {$auditdelete} {
	upvar deleteFiles deleteFiles
    }
    set totalfiles 0

    if {$expand} {

	# Escape any {} characters, as they are special to tcl.  Don't
	# do it twice, though.
	regsub -all {([^\\])(\{|\})} $dir {\1\\\2} dir

	if {[catch {set fnames [glob "$dir{.?*,*}"]} emsg] != 0} {
	    auditmsg $emsg
	    return 0
	}
    } else {
	set fnames [list $dir]
    }
    set excludedone 0
    foreach fname $fnames {
	if {[file tail $fname] == ".."} {
	    continue
	}
	incr totalfiles

	# Need to use "file type" because "file isdirectory" will report
	#  a symlink to a directory as a directory instead of a link and
	#  normally we want to treat them as files, not directories
	set ftype [file type $fname]
	set isdirectory [expr {$ftype == "directory"}]
	if {$isdirectory && $expand} {
	    append fname "/"
	}

	set relname [string range $fname $relStart end]

	if {([lindex [substitutePath $relname] 1] == "") && ($relname != "")} {
	    set excludedone 1
	    debugmsg "$relname excluded"
	    continue
	}

	#
	# descend into a directory first whether it is one of the known paths
	#   or not, so we'll see all extra files in the directory.
	# $relname will be "" when processing installTop; check for it in
	#   addition to $isdirectory because it may be a symlink to a
	#   directory and we should descend into it in that case.
	#
	if {$isdirectory || ($relname == "")} {
	    incr totalfiles [auditextradir $fname $relStart 1]

	    if {$relname == ""} {
		continue
	    }
	}

	if {![info exists knownPaths($relname)]} {
	    auditmsg "$relname is extra $ftype"
	    if {$auditdelete} {
		lappend deleteFiles $relname $fname
	    }
	} else {
	    auditok $relname $ftype
	}
    }

    if {$excludedone} {
	# If any file inside directory was excluded, mark parent directories
	#   as known so they won't be considered extra.
	set parent [string range $dir $relStart end]
	if {$parent != ""} {
	    while {($parent != "./") && ![info exists knownPaths($parent)]} {
		set knownPaths($parent) ""
		set parent "[file dirname $parent]/"
	    }
	}
    }
    return $totalfiles
}
