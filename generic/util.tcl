#
# General TCL utilities for use in NSBD.  Includes logging functions,
#   time handling functions, and many other miscellaneous functions.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 12 Nov 1996
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

#
# windex : word index; split a string on whitespace characters and
#   then treat it like a list
#
set whitespace " \t\n\r"
proc windex {string index} {
    global whitespace
    regsub -all "\[$whitespace\]+" $string " " string
    return [lindex [split $string] $index]
}

#
# wrange : word range; split a string on whitespace characters,
#   then treat it like a list, then join the result back with a blank
#
proc wrange {string first last} {
    global whitespace
    regsub -all "\[$whitespace\]+" $string " " string
    return [join [lrange [split $string] $first $last]]
}

#
# isDirectory: return 1 if the last character of $path is a "/"
# This would be easy to write in C and probably significantly faster.
#
proc isDirectory {path} {
    return [expr {[string index $path [expr {[string length $path] - 1}]] == "/"}]
}

#
# alwaysEvalFor: always evaluate the alwaysscript after the
#    evalscript even if there was an error in the evalscript.
#    errorPrefix, if nonempty, is a prefix to put on any error message.
#
proc alwaysEvalFor {errorPrefix alwaysscript evalscript} {
    set code [catch {uplevel $evalscript} string]
    uplevel $alwaysscript
    if {($code == 1) && ($errorPrefix != "")} {
	set string [addErrorPrefix $errorPrefix $string]
    }
    global errorInfo errorCode
    return -code $code -errorinfo $errorInfo -errorcode $errorCode $string
}

#
# add an error prefix, trying to avoid making lines that are too long
#
proc addErrorPrefix {prefix string} {
    set strlen [string first $string "\n"]
    if {$strlen < 0} {
	set strlen [string length $string]
    }
    if {([string length $prefix] + $strlen) > 72} {
	return "$prefix:\n  $string"
    }
    return "$prefix: $string"
}

#
# Convenient interface to alwaysEvalFor for most common usage: opening a file.
# fdName is the name of a variable to use for the open file descriptor,
#   filename is the name of the file, access is the access string ("r", "w",
#   etc.", and $evalscript is the script to execute while the file is open.
#
proc withOpen {fdName filename access evalscript} {
    set fd [notrace {uplevel [list open $filename $access]}]
    uplevel "set $fdName $fd"
    set code [catch {uplevel $evalscript} string]
    uplevel "close \$$fdName"
    if {$code == 1} {
	set string [addErrorPrefix $filename $string]
    }
    global errorInfo errorCode
    return -code $code -errorinfo $errorInfo -errorcode $errorCode $string
}

#
# Ensure that the directory for toPath exists, but first try the evalscript
#  operation; if it fails with "[Nn]o such file or directory", then create
#  the parent directories and try again.  If toPath is not passed, defaults
#  to the last item in evalscript.
#

proc withParentDir {evalscript {toPath ""}} {
    global errorInfo errorCode
    set code [catch {uplevel $evalscript} string]
    if {($code != 0) && ([string first "o such file or directory" $string] >= 0)} {
	if {$toPath == ""} {
	    # Is there no tcl command that simply returns its parameters???
	    # I can't think of one, so use list + lindex
	    set toPath [lindex [uplevel "list [lindex $evalscript end]"] 0]
	}
	set code [catch {file mkdir [file dirname $toPath]} string]
	if {$code == 0} {
	    set code [catch {uplevel $evalscript} string]
	}
    }
    return -code $code -errorinfo $errorInfo -errorcode $errorCode $string
}

#
# Rename a file to a unique name in the temporary directory if it can't
#   be deleted due to a "text busy" message.  This is in particular for
#   operating systems that don't allow running program files to be deleted
#   (such as HPUX 10).
#
proc robustDelete {file temporarydir} {
    set code [catch {file delete -force $file} deleteErrormsg]
    if {$code == 0} {
	return
    }
    if {![regexp {: .*text .*busy} $deleteErrormsg]} {
	# Check also for permission denied which is what cygwin returns
	#  for a busy executable.
	# Unfortunately that will result in an extra bogus error after the
	#  rename fails if it is truly permission denied so if both fail
	#  with permission denied only print the delete error.
	if {![regexp {: .*permission denied} $deleteErrormsg]} {
	    nsbderror $deleteErrormsg
	}
    }
    global renameNumber renamePrefix
    if {![info exists renamePrefix]} {
	set renamePrefix ".deleted/[pid]"
    }
    if {![info exists renameNumber]} {
	set renameNumber 0
    }
    incr renameNumber
    while {[file exists [set newname \
		[file join $temporarydir "$renamePrefix.$renameNumber"]]]} {
	incr renameNumber
    }
    set code [catch {withParentDir {file rename $file $newname}} renameErrormsg]
    if {$code == 0} {
	updatemsg "Renamed $file because\n  $deleteErrormsg"
	return
    }
    if {[regexp {: .*permission denied} $deleteErrormsg] &&
	    [regexp {: .*permission denied} $renameErrormsg]} {
	# if both were permission denied, just print the delete error message
	nsbderror $deleteErrormsg
    }
    nsbderror "Attempted to rename $file because\n    $deleteErrormsg\n  but couldn't rename it to $newname because\n    $renameErrormsg"
}

#
# Return the real type of a path or an empty string if the file doesn't exist.
# Can't use "file exists" to test for existence of a file because a symlink
#  pointing nowhere will return true.  "file type" will raise an error if
#  a path doesn't exist which is a little messy, so encapsulate it in this
#  function

proc robustFileType {path} {
    if {[catch {file type $path} pathType] == 0} {
	return $pathType
    }
    global errorCode errorInfo
    if {[lindex $errorCode 1] == "ENOENT"} {
	return ""
    }
    error $pathType $errorInfo $errorCode
}

#
# Do glob -nocomplain to expand a file pattern and also recognize symlinks
#  that point nowhere when there are no wildcards; regular glob doesn't do
#  that.
#

proc robustGlob {pattern} {
    set ans [glob -nocomplain $pattern]
    if {$ans != ""} {
	return $ans
    }
    if {[robustFileType $pattern] != ""} {
	return $pattern
    }
    return ""
}

#
# Append items in arg1 and args to list if and only if the items are not
#   already on the list.
# Return the number of items that were not already on the list
#
proc luniqueAppend {varName arg1 args} {
    upvar $varName var
    set changes 0 
    if {![info exists var] || ([lsearch -exact $var $arg1] < 0)} {
	set lastval [lappend var $arg1]
	incr changes
    }
    foreach arg $args {
	if {[lsearch -exact $var $arg] < 0} {
	    set lastval [lappend var $arg]
	    incr changes
	}
    }
    return $changes
}

#
# Sort a list in ascii increasing order and delete duplicates
#
proc lsortUnique {list} {
    set list2 ""
    set previtem ""
    foreach item [lsort $list] {
	if {[string compare $previtem $item] != 0} {
	    lappend list2 $item
	    set previtem $item
	}
    }
    return $list2
}

#
# Insert item into a sorted list if and only if the item is not
#   already on the list.
# Return 0 if the item was already on the list or 1 if it was not
#
proc luniqueInsert {varName item} {
    upvar $varName list
    set idx 0
    if {[info exists list]} {
	foreach litem $list {
	    set comp [string compare $litem $item]
	    if {$comp == 0} {
		return 0
	    }
	    if {$comp > 0} {
		set list [linsert $list $idx $item]
		return 1
	    }
	    incr idx
	}
    }
    lappend list $item
    return 1
}

#
# Return item number in list of glob expressions that matches string,
#   or -1 if none.
# If a list item ends in /, it matches anything beyond that.
#
proc lpathmatch {globlist string} {
    set n 0
    foreach pat $globlist {
	if {[string index $pat [expr [string length $pat] - 1]] == "/"} {
	    append pat "*"
	}
	if {[string match $pat $string]} {
	    return $n
	}
	incr n
    }
    return -1
}


#
# Substitute all occurrences of the regular expression $exp in all
#   the strings in $strings with all of the substitute specifications
#   in subSpecs.  Return a list of all the substitute strings.
#
proc multiSubstitute {exp strings subSpecs} {
    set newStrings ""
    foreach string $strings {
	if {[regexp $exp $string]} {
	    foreach subSpec $subSpecs {
		regsub -all $exp $string $subSpec newString
		lappend newStrings $newString
	    }
	} else {
	    lappend newStrings $string
	}
    }
    return $newStrings
}

#
# Convert a glob pattern into a regular expression pattern
#
proc glob2regexp {pat} {
    regsub -all {\.} $pat {\.} pat
    regsub -all {\*} $pat {.*} pat
    regsub -all {\?} $pat {.} pat
    return $pat
}

#
# Return 1 if file1 and file2 have the same contents, otherwise 0.
# The two files must be text files, not binary files.
#
proc compareFiles {file1 file2} {
    notrace {file stat $file1 stat1}
    notrace {file stat $file2 stat2}
    if {$stat1(size) != $stat2(size)} {
	return 0
    }
    withOpen fd1 $file1 "r" {
	withOpen fd2 $file2 "r" {
	    while {[set buf [read $fd1 1024]] != ""} {
		if {[read $fd2 1024] != $buf} {
		    return 0
		}
	    }
	}
    }
    return 1
}

#
# Return complete path to executable in PATH, or empty if not found
#
proc whereExecutable {executable} {
    global env
    foreach dir [split $env(PATH) ":"] {
	set f [file join $dir $executable]
	if {[file executable $f] && [file isfile $f]} {
	    return $f
	}
    }
    return ""
}

#
# Expand tildes in path name.  I can't find an easy way to do this
#  directly in tcl, so need to cd to the directory and get pwd.
#

proc expandTildes {filename} {
    if {[string index $filename 0] != "~"} {
	return $filename
    }
    set savepwd [pwd]
    # create the directory if it doesn't yet exist
    set dirname [file dirname $filename]
    notrace {file mkdir $dirname}
    cd $dirname
    set filename [file join [pwd] [file tail $filename]]
    cd $savepwd
    return $filename
}

#
# do some system calls for the filesystem, expanding tildes if any before
#   invoke a C function to do the real system call
#
proc hardLink {fromFile toFile} {
    return [primitiveHardLink [expandTildes $fromFile] [expandTildes $toFile]]
}

proc symLink {fromFile toFile} {
    return [primitiveSymLink [expandTildes $fromFile] [expandTildes $toFile]]
}

proc changeMode {path mode} {
    return [primitiveChangeMode [expandTildes $path] $mode]
}

proc changeGroup {path group} {
    return [primitiveChangeGroup [expandTildes $path] $group]
}

proc changeMtime {path mtime} {
    return [primitiveChangeMtime [expandTildes $path] $mtime]
}

#
# Get the name of the shell (as long as it isn't csh)
#
proc getshell {} {
    global env
    if {[info exists env(SHELL)]} {
	set shell $env(SHELL)
	if {![regexp {csh$} $shell]} {
	    # csh will break things, don't use it
	    return $env(SHELL)
	}
    }
    return "sh"
}

#
# pipe to or from a shell command
# access is "r" or "w"
#

proc popen {command access} {
    set shell [getshell]
    # redirect stderr to stdout. Need space after open paren to
    #   avoid causing ksh to do an undesired level of evaluation.
    set com ""
    append com "( " $command ") 2>&1"
    debugmsg "popen \"$com\" \"$access\""
    return [open [list "|$shell" -c $com] $access]
}

#
# If "reloc" is not empty or is just "=", open a binary relocate running in a
#  sub-process that applies the "reloc" translation, otherwise just open a
#  regular file.  Put the $fd into binary mode too, and put notrace around
#  the system calls that may get errors to avoid any stack trace dumps.
#
proc openbreloc {fname reloc access {mode ""}} {
    if {($reloc == "") || ($reloc == "=")} {
	set fd [notrace {
	    if {$mode == ""} {
		# if mode missing when creating, defaults to 0666, but
		#  an empty string is an error
		open $fname $access
	    } else {
		open $fname $access $mode
	    }
	}]
	fconfigure $fd -translation binary
	return $fd
    }
    global brelocPath
    if {![info exists brelocPath]} {
	global cfgContents
	if {[info exists cfgContents(breloc)]} {
	    set brelocPath $cfgContents(breloc)
	} else {
	    set brelocPath [whereExecutable "breloc"]
	    if {$brelocPath != ""} {
		set brelocPath "$brelocPath -r"
	    }
	}
    }
    set breloc $brelocPath
    if {$breloc == ""} {
	nsbderror "breloc not found"
    }
    global brelocTmpnames
    global brelocTmpnum
    if {(![info exists brelocTmpnum]) || ([incr brelocTmpnum] >= 100)} {
	set brelocTmpnum 1
    }
    set tmpname [scratchAddName "bre$brelocTmpnum"]
    if {$access == "w"} {
	file delete -force $fname
	file mkdir [file dirname $fname]
	set modecmd ""
	if {$mode != ""} {
	    set modcmd "chmod $mode $fname;"
	} 
	set fd [notrace {popen "( $modcmd exec $breloc $reloc ) 2>$tmpname >$fname" "w"}]
    } else {
	set fd [notrace {popen "exec $breloc $reloc 2>$tmpname <$fname" "r"}]
    }
    set brelocTmpnames($fd) $tmpname
    fconfigure $fd -translation binary
    return $fd
}

#
# close the binary relocate or any file descriptor.
#
proc closebreloc {fd} {
    global brelocTmpnames
    if {![info exists brelocTmpnames($fd)]} {
	close $fd
	return
    }
    set tmpname $brelocTmpnames($fd)
    unset brelocTmpnames($fd)
    if {[catch {close $fd}] != 0} {
	set errfd [notrace {open $tmpname "r"}]
	set errmsg [read $errfd]
	close $errfd
	scratchClean $tmpname
	nsbderror "breloc error: $errmsg"
    }
    scratchClean $tmpname
}

#
# figure out the verboseLevel
#
proc verboseLevel {} {
    global cfgContents
    if {[info exists cfgContents(verbose)]} {
	return $cfgContents(verbose)
    } else {
	return 4
    }
}

#
# Return a filename with a prefix on the tail
#
proc addFilePrefix {fileName prefix} {
    set dirName [file dirname $fileName]
    if {$dirName == "."} {
	set dirName ""
    }
    return [file join $dirName $prefix[file tail $fileName]]
}

#
# Indent each line in a multiple-line string 2 spaces
# This is mostly called with strings that do not *end* in a newline,
#   so don't worry about an extra indent in that case
#
proc indent2 {msg} {
    regsub -all "\n" $msg "\n  " msg
    return "  $msg"
}

#
# log a message, which may contain newlines.  If $level is less than or
#   equal to logLevel configuration keyword, write it to the logFile with
#   a timestamp.  If the message is less than or equal to the verbose level,
#   also write interactively.
# levels:
#	0 - error
#	1 - warning
#	2 - notice from maintainer
#	3 - update
#	4 - progress info
#	5 - transfer info (and url fetch/post percent-done messages for
#           those > 3 seconds, not done by this routine)
#	6 - (url fetch/post percent-done messages for all, not done here)
#	7 - debug
#
proc logmsg {level msg} {
    global errorInfo errorCode
    set savErrorInfo $errorInfo
    set savErrorCode $errorCode
    set code [catch {
	set logged 0
	global cfgContents
	if {[info exists cfgContents(logFile)]} {
	    set logFile $cfgContents(logFile)
	} else {
	    set logFile "updates.log"
	}
	if {[info exists cfgContents(logLevel)]} {
	    set logLevel $cfgContents(logLevel)
	} else {
	    set logLevel 3
	}
	if {($level <= $logLevel) && [info exists cfgContents(nsbdpath)] &&
		    ($cfgContents(nsbdpath) != "")} {
	    set fname [file join $cfgContents(nsbdpath) $logFile]
	    trimOldLog $fname
	    set fd [notrace {withParentDir {open $fname "a"} $fname}]
	    alwaysEvalFor $fname {close $fd} {
		set now [logTime]
		foreach line [split $msg "\n"] {
		    puts $fd "$now $line"
		}
	    }
	}
	global messagesWindow
	if {($messagesWindow != "") && 
		    (($level <= 2) || ($level <= [verboseLevel]))} {
	    $messagesWindow insert end "$msg\n"
	    $messagesWindow see end
	    update idletasks
	} elseif {$level <= [verboseLevel]} {
	    if {$level == 0} {
		puts -nonewline stderr "nsbd: "
	    }
	    puts stderr $msg
	    flush stderr
	}
    } string]
    if {$code > 0} {
	puts stderr "Error in logging message:"
	puts stderr [indent2 $errorInfo]
	puts stderr "  Original message was: $msg"
	if {$level == 0} {
	    puts stderr "  Original stack trace was:"
	    puts stderr "[indent2 [indent2 $savErrorInfo]]"
	}
	# avoid error handler to prevent recursive call to broken logmsg
	nsbdExit 1
    }
    set errorInfo $savErrorInfo
    set errorCode $savErrorCode
}

#
# Log an error message.
#
proc errormsg {msg} {
    logmsg 0 $msg
}

#
# Log a warning message.
#
proc warnmsg {msg} {
    logmsg 1 $msg
    global messagesWindow
    if {$messagesWindow != ""} {
	set ans [tk_dialog .warnmsg "Warning" $msg warning 0 "Ok" "Exit"]
	if {$ans == 1} {
	    nsbdExit 1
	}
    }
}

#
# Log other kinds of messages
#
proc noticemsg {msg} {
    logmsg 2 $msg
}

proc updatemsg {msg} {
    logmsg 3 $msg
}

proc progressmsg {msg} {
    logmsg 4 $msg
}

proc transfermsg {msg} {
    logmsg 5 $msg
}

proc debugmsg {msg} {
    logmsg 7 $msg
}

#
# Check for an old log file the first time the log file is accessed.
# If the first entry is more then logDays old, rename existing log with an
#   "old" prefix.

proc trimOldLog {fname} {
    global logFileHasBeenChecked
    if {[info exists logFileHasBeenChecked]} {
	return
    }
    set logFileHasBeenChecked 1

    global cfgContents
    if {[info exists cfgContents(logDays)]} {
	set logDays $cfgContents(logDays)
    } else {
	set logDays 7
    }
    if {$logDays == 0} {
	return
    }
    catch {file stat $fname statb}
    if {![info exists statb(mtime)]} {
	return
    }
    set modtime $statb(mtime)
    unset statb
    withOpen fd $fname "r" {
	gets $fd line
    }
    set firstTime ""
    regexp {([^ ]* [^ ]*)( .*)} $line x firstTime
    if {[catch {scanAnyTime $firstTime} firstSeconds] != 0} {
	set firstSeconds 0
    }
    set nowSeconds [clock seconds]
    set daysOld [expr {($nowSeconds - $firstSeconds) / (24 * 60 * 60)}]
    if {$daysOld <= $logDays} {
	debugmsg "$fname was $daysOld days old, not renaming"
	return
    }
    set oldfname [addFilePrefix $fname "old"]
    lockFile $fname
    catch {file stat $fname statb}
    if {![info exists statb(mtime)] || ($modtime != $statb(mtime))} {
	unlockFile $fname
	debugmsg "Didn't lock $fname before it was modified, skipping this time"
	return
    }
    file delete -force $oldfname
    notrace {file rename $fname $oldfname}
    unlockFile $fname
    if {$firstSeconds == 0} {
	progressmsg "Couldn't scan time on first line of $fname\n   renamed it to $oldfname"
    } else {
	progressmsg "Log file $fname was $daysOld days old\n  renamed it to $oldfname"
    }
}

#
# Lock a file.  Create lock file with exclusive create permission.  If
#  file already exists, try up to 5 times one second apart.  If the
#  modification time of the lock file or $file changes, assume another
#  program is making progress and reset the count.  If neither changes
#  after 5 seconds, assume the other program has died and forcibly remove
#  the lock before retrying.
# NOTE: perhaps this should be changed to use the Unix 'fcntl' F_SETLK
#  facility.  I'm not sure how portable that would be though.  It's nice
#  in that it can distinguish between read locks and read/write locks.
#

proc lockFile {filename} {
    debugmsg "Obtaining lock on $filename"
    if {![file writable [file dirname $filename]]} {
	nsbderror "Unable to obtain lock on $filename because directory not writable"
    }
    set lockname [addFilePrefix $filename LCK]
    set tries 0
    set modtime 0
    while {$tries <= 5} {
	set code [catch {set fd [open $lockname "WRONLY CREAT EXCL"]} why]
	if {$code == 0} {
	    puts $fd [pid]
	    close $fd
	    addToScratchFiles $lockname
	    return
	}
	incr tries
	after 1000
	foreach file {$lockname $filename "last"} {
	    if {$file == "last"} {
		if {$tries >= 5} {
		    progressmsg "Overriding $lockname, lock held at least 5 seconds"
		    notrace {file delete $lockname}
		    set tries 0
		}
	    } else {
		catch {unset statb}
		catch {file stat $file statb}
		if {[info exists statb(mtime)]} {
		    if {$statb(mtime) > $modtime} {
			set modtime $statb(mtime)
			set tries 0
			break
		    }
		}
	    }
	}
    }
    nsbderror "$why"
}

#
# Remove the lock file
#
proc unlockFile {filename} {
    debugmsg "Releasing lock on $filename"
    scratchClean [addFilePrefix $filename LCK]
}

#
# Center the window on the screen.  This code is borrowed from tk_dialog
#
proc tkCenter {{win "."}} {
    wm withdraw $win
    update idletasks
    set x [expr {([winfo screenwidth $win] - [winfo reqwidth $win]) / 2}]
    set y [expr {([winfo screenheight $win] - [winfo reqheight $win]) / 2}]
    wm geom $win +$x+$y
    wm deiconify $win
}

#
# pop up messages window
#
proc makeMessagesWindow {} {
    global messagesWindow

    set mw ".messages"
    toplevel $mw
    wm title $mw "NSBD messages"
    text $mw.text -width 80 -height 35 -yscrollcommand "$mw.scroll set"
    scrollbar $mw.scroll -command "$mw.text yview" -takefocus 0
    pack $mw.scroll -side right -fill y
    pack $mw.text -side left -fill x -expand 1
    tkCenter $mw
    set messagesWindow $mw.text
    update idletasks
}

#
# remove messages window
#
proc deleteMessagesWindow {} {
    global messagesWindow

    destroy $messagesWindow
    set messagesWindow ""
}

#
# raise the messages window
#
proc raiseMessagesWindow {} {
    global messagesWindow

    wm withdraw .messages
    wm deiconify .messages
    update idletasks
}

#
# hide the messages window
#
proc hideMessagesWindow {} {
    global messagesWindow
    wm withdraw .messages
    update idletasks
}

#
# Compare two version numbers.  Return negative if version1 is less than
#   version2, 0 if the versions are equal, or positive if version1 is greater
#   than version2.
#
proc compareVersions {version1 version2} {
    while {[string compare $version1 $version2] != 0} {
	set n1 ""; set a1 ""; set r1 ""
	set n2 ""; set a2 ""; set r2 ""
	regexp {^([0-9]*)([^0-9]*)(.*)} $version1 x n1 a1 r1
	regexp {^([0-9]*)([^0-9]*)(.*)} $version2 x n2 a2 r2
	if {$n1 < $n2} {
	    return -1
	}
	if {$n1 > $n2} {
	    return 1
	}
	# alpha or beta suffixes are considered to be less than
	#   a number without an alpha or beta suffix
	set pre1 [expr {[string first [string index $a1 0] "AaBb"] >= 0}]
	set pre2 [expr {[string first [string index $a2 0] "AaBb"] >= 0}]
	if {$pre1 && !$pre2} {
	    return -1
	}
	if {!$pre1 && $pre2} {
	    return 1
	}
	if {[set comp [string compare $a1 $a2]] != 0} {
	    return $comp
	}
	set version1 $r1
	set version2 $r2
    }
    return 0
}

#
# run clock with gmt time zone
#

proc gmtclock {args} {
    # also set TZ environment variable, since -gmt option of "clock"
    #   appears to be off by an hour sometimes; it was observed on a
    #   Solaris 5.3 system with the TZ set to "US/Central" while in
    #   daylight savings time.
    global env
    if {[info exists env(TZ)]} {set svtz $env(TZ)}
    set env(TZ) GMT
    set result [eval clock $args "-gmt 1"]
    if {[info exists svtz]} {set env(TZ) $svtz} else {unset env(TZ)}
    return $result
}

#
# Return the current date and time
#
proc currentTime {} {
    return [httpTime]
}

#
# Return time in preferred http format.  If a parameter is given, it is
#  assumed to be a time in seconds like [clock seconds], otherwise the
#  current time is used.
#
proc httpTime {{seconds ""}} {
    if {$seconds == ""} {
	set seconds [clock seconds]
    }
    return [gmtclock format $seconds -format {%a, %d %b %Y %H:%M:%S GMT}]
}

#
# Return time current time for log file.
#
proc logTime {} {
    return [gmtclock format [clock seconds] -format {%Y/%m/%d %H:%M:%S}]
}

#
# Scan any time format and convert into "seconds" format
#
# Accepts any of the three official HTTP/1.0 formats:
#     Sun, 06 Nov 1994 08:49:37 GMT (preferred)
#     Sunday, 06-Nov-94 08:49:37 GMT
#     Sun Nov  6 08:49:37 1994
# and the old and new style PGP times
#     1994/11/06 08:49 GMT
#     Sun Nov  6 08:49:37 1994 GMT
# and the logTime format (GMT assumed)
#     1994/11/06 08:49:37
# and more, depending on what Tcl's [clock scan] can handle

array set weekdayTable "Sun {} Mon {} Tue {} Wed {} Thu {} Fri {} Sat {}"

proc scanAnyTime {time} {
    global weekdayTable
    set time [string trim $time]
    set tz ""
    if {[info exists weekdayTable([string range $time 0 2])]} {
	# get rid of the day of the week, and turn dashes into spaces
	set time [lrange $time 1 end]
	regsub -all -- "-" $time " " time
    } elseif {[scan $time "%d/%d/%d %d:%d:%d %s" year mon day hour min sec tz] >= 6} {
	set time [format "%02d:%02d:%02d %02d/%02d/%02d %s" \
				$hour $min $sec $mon $day $year $tz]
    } elseif {[scan $time "%d/%d/%d %d:%d %s" year mon day hour min tz] >= 5} {
	set time [format "%02d:%02d %02d/%02d/%02d %s" \
				$hour $min $mon $day $year $tz]
    }
    return [gmtclock scan $time]
}

#
# Canonicalize the time to be the format
#     Sun, 06 Nov 1994 08:49:37 GMT
#
proc canonicalizeTime {time} {
    return [httpTime [scanAnyTime $time]]
}

#
# Compare two times.  Return negative if time1 is less than time2,
#   0 if the times are equal, or positive if time1 is greater than time2.
#
proc compareTimes {time1 time2} {
    set time1seconds [scanAnyTime $time1]
    set time2seconds [scanAnyTime $time2]
    if {$time1seconds < $time2seconds} {
	return -1
    }
    if {$time1seconds > $time2seconds} {
	return 1
    }
    return 0
}
