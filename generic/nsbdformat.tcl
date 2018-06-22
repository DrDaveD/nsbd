#
# Functions to parse and generate "nsbd" format files.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 05 Nov 1996
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
# empty procedure for auto loading this file
#
proc ensure-nsbdformat-loaded {} {
}

# 
# General format of each line.  This is a TCL list of lines to make it easier
#   to be used in generating templates.
#
set nsbdFormatSummary {
{General format of each non-commentary line: keyword plus colon (:) followed}
{by whitespace followed by value.  The value may instead be indented any amount}
{on the following line.  If there is no value, the keyword is ignored.}
{If the value is a list of items, the items can be comma-separated on the same}
{line as the keyword, or the first item may be indented on the following}
{line and subsequent items indented the same amount on lines after that.}
{Sub-keywords, if any, must be indented further on lines below a list item.}
}

set nsbdFormatSpec {
This is a detailed description of the file format of NSBD files:
    0. ".nsb" files may be digitally signed with multiple signatures (although
	currently only one PGP signature is supported).  Signature blocks are
	placed at the end of ".nsb" files, but if they are there a line should
	be present at the beginning of the file beginning with five dashes
	(-----) and the signature type.  If the file does begin with five
	dashes, all lines up through the first blank line are ignored.
	Signature blocks are surrounded by lines that start with five dashes.
	Signatures should not include the beginning dashed lines, other
	signature blocks, and beginning and ending blank lines, and should
	treat all lines as if they end with carriage return and line feed.
    1. Lines beginning with a pound sign (#), possibly preceded by white
	space, or blank lines are ignored.
    2. The first non-ignored line of the file always contains a keyword
	that identifies the file type and version.
    3. Lines are terminated by any combination of line feed and carriage
	return characters.
    4. All data items are marked by a keyword and a colon (:).
    5. Keywords that are unrecognized are silently ignored (unrecognized
	keywords in local-only files may be flagged with warnings).
    6. If the data is short, it may immediately follow the keyword and colon
	on the same line, with optional whitespace (spaces or tabs) between.
    7. Data that follows a keyword on the same line may be a comma-separated
	list.  There should be no whitespace around the commas.
    8. If there is no data on the same line as the keyword, all following
	lines which are at a new "nesting level" (defined below) are combined
	into a list for that keyword.  If there is only one line at the
	new nesting level, the data on that line is treated exactly the same
	as if it were on the same line as the keyword.
    9. If a list is not expected by a keyword but a list is provided, only
	the first item will be used and the rest ignored.  By convention,
	keywords that expect lists are generally plural.
    10. Additional lines at a new nesting level are parsed for new sub-keywords
	for data items below the data item.  Sub-keywords only exist under
	data items of keywords that expect lists, and the list must be
	in the form of one item per line, not the comma-separated list.
    11. Keywords can be in any order at a nesting level.  Duplicate keywords
	at the same nesting level are ignored.
Nesting levels are defined as follows:
    1. Whitespace (spaces or tabs) at the beginning of a line is assigned
	a length.  Each space is worth 1, and each tab increases the length
	to the next multiple of 8.
    2. Any time the length of the whitespace is equal to the previous line,
	it is another line at the same nesting level.
    3. Any time the length of the whitespace is greater than the length on
	the previous line, it designates a new nesting level. 
    4. Any time the length of the whitespace is less than the previous line,
	it must match the length of a previous nesting level or it is an
	error.
}

#
# Determine the fileType of the file open on file descriptor $fd.
# If given, $expectedType is the expected fileType.
# Returns a list of three items:
#   1. the fileType, 
#   2. the number of lines read from the file to determine the file type
#   3. a boolean that is 1 if the file contains a PGP signature or 0
#        if it does not
#
proc nsbdFileType {fd {expectedType ""}} {
    global fileKeywords fileTypes fileVersions
    gets $fd line
    set lineno 1
    set hassig 0
    while {[string range $line 0 4] == "-----"} {
	if {[string range $line 0 28] == "-----BEGIN PGP SIGNED MESSAGE"} {
	    set hassig 1
	}
	while {![eof $fd] && ([string trim $line] != "")} {
	    # ignore up through the first blank line
	    gets $fd line
	    incr lineno
	}
	# ignore beginning blank line
	gets $fd line
	incr lineno
    }
    set line [string trim $line]
    while {![eof $fd] && (($line == "") || ([string index $line 0] == "#"))} {
	set line [string trim [gets $fd]]
	incr lineno
    }
    set firstKey [windex $line 0]
    if {$expectedType != ""} {
	set expectedKey $fileKeywords($expectedType):
	if {$expectedKey != $firstKey} {
	    nsbderror "first non-commentary line does not contain \"$expectedKey\":\n  $line"
	}
    }
    set firstKeyEnd [expr [string length $firstKey] - 1]
    if {[string index $firstKey $firstKeyEnd] != ":"} {
	global fileTitles
	set msg \
{first non-commentary line does not begin with a recognized keyword
  followed by a colon and version number.  Recognized keywords are:}
	set n 0
	foreach fileType {cfg nrd npd nsb} {
	    incr n
	    append msg "\n    $fileTitles($fileType) file: "
	    append msg "\"$fileKeywords($fileType): $fileVersions($fileType)\""
	}
	nsbderror $msg
    }
    set firstKey [string range $firstKey 0 [expr $firstKeyEnd - 1]]
    if {![info exists fileTypes($firstKey)]} {
	set keys ""
	foreach {nam val} [array get fileKeywords] {
	    lappend keys $val
	}
	set msg "first non-commentary line does not contain an allowed keyword:"
	append msg "\n    $line"
	append msg "\n  must be one of:"
	append msg "\n    [lsort $keys]"
	nsbderror $msg
    }
    set fileType $fileTypes($firstKey)
    set expectedVersion $fileVersions($fileType)
    set version [wrange $line 1 end]
    if {$version != $expectedVersion} {
	nsbderror [concat "unrecognized \"$firstKey\" version $version," \
		"expected $expectedVersion"]
    }
    return [list $fileType $lineno $hassig]
}

# nsbdParseContents parses an open file in "nsbd" format into a Tcl array,
#  after the fileType has been already read and determined
# It takes five parameters:
#  1. an open file identifier fd.  The first line of the file is assumed
#	to already have been read.
#  2. the fileType of the file being read
#  3. the number of lines already read from the file
#  4. the filename (for warning messages)
#  5. an arrayname in which to install the keywords
#  and returns the array name.  All parsed keywords are installed in the
#  same array; if there are sub-keywords below a keyword, the sub-keyword
#  is added to a tcl list containing the keyword and that list becomes the
#  index into the array.  If a sub-keyword is below an item in an "nsbd list"
#  in the file, that "nsbd list" item is included in the tcl list that
#  is the index into the array.
# NOTE 1999/12/7: this should be rewritten in C.  On slow machines and large
#  files, this implementation takes a lot of CPU time and uses up a lot more
#  virtual memory than necessary.

proc nsbdParseContents {fd fileType lineno filename arrayname} {
    upvar #0 ${fileType}Keytable keytable
    upvar $arrayname array
    nsbdnestlevelInit
    set arraykey ""
    set keytabkey ""
    set prevnestlevel 0
    set inlist(0) 0
    set inlist(1) 0
    set skipkeyword 0
    while {[set linelength [gets $fd line]] >= 0} {
	if {[string range $line 0 4] == "-----"} {
	    break
	}
	incr lineno
	set answer [nsbdnestlevel $line $linelength $lineno]
	set nestlevel [lindex $answer 0]
	set whitechars [lindex $answer 1]
	if {($whitechars == $linelength) ||
				([string index $line $whitechars] == "#")} {
	    # skip blank lines and comments
	    continue
	}
	set realline [string trimright [string range $line $whitechars end]]
	if {$skipkeyword} {
	    if {$nestlevel > $prevnestlevel} {
		# ignore sub-keywords at higher nesting levels
		continue
	    }
	    set skipkeyword 0
	}
	if {$nestlevel < $prevnestlevel} {
	    # trim down the keytabkey to this level.
	    # this is tricky because keytabkey does not include elements
	    #   for nesting levels that are lists.  Trim off the elements
	    #   that correspond to nesting levels that are not lists.
	    # can't assume here that every odd-numbered level is "inlist"
	    #   because if there's a single item in a list it is allowed to
	    #   immediately follow the keyword.
	    set keylen -1
	    for {set n 0} {$n <= $nestlevel} {incr n} {
		if {!$inlist($n)} {
		    incr keylen
		}
	    }
	    set keytabkey [lrange $keytabkey 0 $keylen]
	}
	if {$inlist($nestlevel)} {
	    # only a value on this line, no keyword
	    set value $realline
	    if {$keytable($keytabkey)} {
		# list is expected
		# trim down arraykey the array key to this level
		set arraykey [lrange $arraykey 0 [expr $nestlevel - 1]]
		if {!$noappend || ![info exists array($arraykey)]} {
		    # append this value to the list at this nesting level
		    lappend array($arraykey) $value
		    set noappend 0
		}
		# append value to the arraykey in case there are any subkeys
		lappend arraykey $value
	    } elseif {![info exists array($arraykey)]} {
		# value is not expected to be a list, store only first item
		set array($arraykey) $value
	    }
	    set prevnestlevel $nestlevel
	    continue
	}
	# new keyword on this line
	# note that the following regexp allows there to be no whitespace
	#  after the colon; I could save the whitespace and then if there
	#  is a non-empty value make sure that the whitespace is not empty,
	#  but instead I think I'll allow the whitespace to be missing
	regexp "^(\[^ \t:\]*)(:)?\[ \t\]*(.*)" $realline x keyword colon value
	if {$colon != ":"} {
	    nsbderror "keyword $keyword on line $lineno is not followed by a colon"
	}
	if {$nestlevel > $prevnestlevel} {
	    # $nestlevel is exactly one greater than $prevnestlevel
	    #   because nestlevels can only increase one at a time
	    lappend arraykey $keyword
	    lappend keytabkey $keyword
	} elseif {$nestlevel == 0} {
	    set arraykey [list $keyword]
	    set keytabkey [list $keyword]
	} else {
	    # $nestlevel <= $prevnestlevel
	    # replace all items in arraykey from current level to end
	    set arraykey [lreplace $arraykey $nestlevel end $keyword]
	    # replace just last item in keytabkey because the rest would
	    #  have been trimmed off above
	    set n [expr [llength $keytabkey] - 1]
	    set keytabkey [lreplace $keytabkey $n $n $keyword]
	}
	if {[info exists keytable($keytabkey)]} {
	    # recognized keyword
	    if {[string length $value] == 0} {
		# this is a keyword with no value; next nestlevel is value list
		set inlist([expr $nestlevel + 1]) 1
		# nestlevel after that if any will be a keyword
		set inlist([expr $nestlevel + 2]) 0
		set noappend 1
	    } else {
		# there is a value, next nestlevel is keyword + value
		set inlist([expr $nestlevel + 1]) 0
		if {![info exists array($arraykey)]} {
		    if {$keytable($keytabkey)} {
			# list is expected
			set value [split $value ","]
			set array($arraykey) $value
			#  append first item to the arraykey in case there are
			#    any subkeys
			lappend arraykey [lindex $value 0]
		    } else {
			# value is not expected to be a list; store item
			set array($arraykey) $value
		    }
		}
	    }
	} else {
	    # unrecognized keyword, skip sub-keys if any
	    set skipkeyword 1
	    global fileWarnUnknownKeys
	    if {$fileWarnUnknownKeys($fileType)} {
		warnmsg "warning: unknown keyword '$keyword' in $filename ignored"
	    }
	}
	set prevnestlevel $nestlevel
    }
    return $arrayname
}

#
# NOTE: nsbdnestlevelInit and nsbdnestlevel are in C for speed
#  and in machine dependent nsbdTclshLib.tcl for when running in tclsh
#

# this is useful for timing nsbdnestlevel separately from just reading
#  the file and from nsbdParseContents
proc nsbdnestleveltest {filename {filealone 0}} {
    nsbdnestlevelInit
    withOpen fd $filename "r" {
	gets $fd line
	set lineno 1
	while {[set linelength [gets $fd line]] >= 0} {
	    incr lineno
	    if {!$filealone} {
		set answer [nsbdnestlevel $line $linelength $lineno]
	    }
	}
    }
}

# nsbdParse parses an nsbd file
# parameters are
#   1. fd - open file descriptor of the file to read from
#   2. expectedFileType - expected nsbd fileType or "" if any will be accepted
#   3. filename - name of the file (for warning messages)
#   4. contentsName - name of array to read the contents into
# Returns the same thing that nsbdFileType returns
#

proc nsbdParse {fd expectedFileType filename contentsName} {
    ensure-tables-loaded
    upvar $contentsName contents
    catch {unset contents}
    set fileTypeAns [nsbdFileType $fd $expectedFileType]
    foreach {fileType lineno hassig} $fileTypeAns {}
    nsbdParseContents $fd $fileType $lineno $filename contents
    return $fileTypeAns
}

# 
# Same as nsbdParse except with a filename instead of a file descriptor
#
proc nsbdParseFile {filename expectedFileType contentsName} {
    upvar $contentsName contents
    debugmsg "Parsing $filename"
    withOpen fd $filename "r" {
	return [nsbdParse $fd $expectedFileType $filename contents]
    }
}

#
# nsbdGen generates an nsbd file
# parameters are
#   1. fd - open file descriptor of the file to write
#   2. fileType - an nsbd fileType
#   3. contentsName - name of array that contains the contents to write
#
proc nsbdGen {fd fileType contentsName} {
    upvar $contentsName contents
    upvar #0 ${fileType}Keys keys
    global fileKeywords fileVersions
    puts $fd "$fileKeywords($fileType): $fileVersions($fileType)"
    walkKeys $keys contents $fileType "nsbdGenWalkproc $fd"
}

# 
# Same as nsbdGen except with a filename instead of a file descriptor
#
proc nsbdGenFile {filename expectedFileType contentsName {comment ""}} {
    upvar $contentsName contents
    debugmsg "Generating $filename"
    withOpen fd $filename "w" {
	if {$comment != ""} {
	    puts $fd $comment
	}
	return [nsbdGen $fd $expectedFileType contents]
    }
}

#
# Procedure to walk over keys while generating a nsbd file
#


proc nsbdGenWalkproc {fd walkType key value} {
    switch $walkType {
	nonListItem {
	    set indentLevel [expr [llength $key] - 1]
	    generateIndent $fd $indentLevel
	    puts $fd "[lindex $key $indentLevel]: $value"
	}
	listTable {
	    # ignore the list table value, will print out each item
	    set indentLevel [expr [llength $key] - 1]
	    generateIndent $fd $indentLevel
	    puts $fd "[lindex $key $indentLevel]:"
	}
	listItem {
	    generateIndent $fd [llength $key]
	    puts $fd "$value"
	}
    }
}

#
# Output an indentation to fd for level.  Convert each 8 spaces into a tab.
#
proc generateIndent {fd level} {
    global indentTable cfgContents
    if {![info exists indentTable($level)]} {
	if {[info exists cfgContents(generatedIndentLength)]} {
	    set length $cfgContents(generatedIndentLength)
	} else {
	    # default for each level is 4
	    set length 4
	}
	set length [expr $length * $level]
	set indent ""
	while {$length > 0} {
	    if {$length >= 8} {
		append indent "\t"
		incr length -8
	    } else {
		append indent " "
		incr length -1
	    }
	}
	set indentTable($level) $indent
    }
    puts -nonewline $fd $indentTable($level)
}

#
# This is just like nsbdGen but it also writes out a comment template
#   in the file
proc nsbdGenTemplate {fd fileType contentsName} {
    upvar $contentsName contents
    upvar #0 ${fileType}Keylist keylist
    global fileKeywords fileVersions fileTitles 
    puts $fd "# Template generated by [nsbdVersion]"
    puts $fd "# This is a NSBD $fileTitles($fileType) file."
    global nsbdFormatSummary
    foreach l $nsbdFormatSummary {
	puts $fd "# $l"
    }
    puts $fd "$fileKeywords($fileType): $fileVersions($fileType)"
    puts $fd ""
    set mainkey ""
    set subkeys ""
    set prevklength 0
    foreach {c k v} $keylist {
	set klength [llength $k]
	if {$klength > 1} {
	    set indent [string range "                " \
				    0 [expr "($klength - 1) * 2"]]
	    if {$prevklength == 1} {
		puts $fd "# Sub-keywords under each:"
	    }
	    puts $fd "#$indent[lindex $k [expr $klength - 1]]"
	    foreach l $c {
		puts $fd "#    $indent$l"
	    }
	    lappend subkeys [lrange $k 1 end]
	} else {
	    if {$prevklength > 0} {
		nsbdGen1Key $fd $mainkey $subkeys contents $fileType
	    }
	    foreach l $c {
		puts $fd "# $l"
	    }
	    set mainkey $k
	    set subkeys ""
	}
	set prevklength $klength
    }
    if {$mainkey != ""} {
	nsbdGen1Key $fd $mainkey $subkeys contents $fileType
    }
}

# generate one top-level key and its subkeys
proc nsbdGen1Key {fd key subkeys contentsName fileType} {
    upvar $contentsName contents
    if {![walk1Key $subkeys contents $fileType \
		[list nsbdGenWalkproc $fd] $key $key]} {
	puts $fd $key:
    }
    puts $fd ""
}

#
# walk the keys and their subkeys in the $contentsName table, performing cmd on
#   each with these 3 parameters added:
#	1. The type of operation
#		- nonListItem: value is a non-list item for the key
#		- listTable: value is the name of a table in which the
#			list can be looked up by the key
#		- listItem: value is a single item in the list for the key
#	2. The key
#	3. The value
proc walkKeys {keys contentsName fileType cmd {contentskey ""} {keytabkey ""}} {
    upvar $contentsName contents
    set key ""
    set subkeys ""
    foreach k $keys {
	if {[llength $k] > 1} {
	    lappend subkeys [lrange $k 1 end]
	} else {
	    if {$key != ""} {
		walk1Key $subkeys contents $fileType $cmd \
			[concat $contentskey $key] [concat $keytabkey $key]
	    }
	    set key $k
	    set subkeys ""
	}
    }
    if {$key != ""} {
	walk1Key $subkeys contents $fileType $cmd \
			[concat $contentskey $key] [concat $keytabkey $key]
    }
}

#
# Walk just the contentskey
# if no value for the key, don't do anything and return 0
# otherwise return 1
#
proc walk1Key {subkeys contentsName fileType cmd contentskey keytabkey} {
    upvar $contentsName contents
    if {![info exists contents($contentskey)] || \
			([set value $contents($contentskey)] == "")} {
	return 0
    }
    upvar #0 ${fileType}Keytable keytable
    if {$keytable($keytabkey)} {
	# value is a list
	eval $cmd [list listTable $contentskey contents]
	foreach item $value {
	    eval $cmd [list listItem $contentskey $item]
	    if {$subkeys != ""} {
		walkKeys $subkeys contents $fileType $cmd \
			[concat $contentskey [list $item]] $keytabkey
	    }
	}
    } else {
	# value is not a list
	eval $cmd [list nonListItem $contentskey $value]
    }
    return 1
}
