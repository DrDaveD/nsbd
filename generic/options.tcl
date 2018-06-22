#
# Handle command-line options.  This file contains a table of the options
#   and all the functions that implement them or at least the beginning part
#   of the implementation before it calls functions in other files.  A
#   performance optimization to read multiple '.nsb' files in a single
#   network transfer is also implemented here in 'procnsbpackages'.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 21 Nov 1996
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
proc ensure-options-loaded {} {
}

# Every third item in the list is the following:
#   1. A list of comment lines that apply to this option, suitable for
#	printed help about the option.  If the comment is empty, it will
#	not be included in help (used for obsolete commands).
#   2. A list of equivalent option names.  There should be corresponding tcl
#	functions that begin with "option".
#   3. A number with one of these possible values:
#	   0. Option takes no parameters.
#	   1. Option takes 1 parameter.  If not given on the command line,
#		option function will be invoked with an empty string.
#	   2. Option takes each remaining non-keyword setting argument
#		from the command line as a parameter.  If there were none,
#		the option function will be invoked once with an empty
#		parameter.
#	   3. Option takes all remaining non-keyword setting arguments from
#		the command line as a list.
#	   4. Option takes the rest of the command line as a string parameter.
#

# these options get processed without needing to read the config file.
# dumpRegistry and dumpConfig are treated as info only options because we
# want to override the normal processing of the registryFile and configFile
# keywords on the command line.  Instead when the dumpRegistry and dumpConfig
# options are processed, we go load any specified cfg or nrd files at that
# time.
set infoOnlyOptions "-help -? -version -V -license -multigetFiles -dumpRegistry -dumpConfig"

set optionList {
 {{Print command-line help.}}
"-help -?" 1

 {{Print the current program version.}}
"-version -V" 0

 {{Print the license (GNU General Public License) and no-warranty details.}}
"-license" 0

 {{Register package described in the '.nsb' file at following filename or URL.}
  {URL may be of type http://, ftp://, rsync://, or file://.  Pops up a window}
  {to request verification of package registry information before registering}
  {and installing.  If a Graphical User Interface display is not available,}
  {register package by hand by editting 'registry.nrd' with information from}
  {the package's '.nsb' file and use '-update' on the package.}}
"-register" 1

 {{Check registered packages for updates and install the updates.  If package}
  {name is the special name "all", will check all registered packages.}
  {Here is a special case useful for installing packages from within a single}
  {computer: if nsbUrl and topUrl are specified on the command line with a URL}
  {type of file:// (and there's no multigetUrl), files will be installed from}
  {a local filesystem rather than over a network.}}
"-update" 3

 {{Same as -update except that only one package may be checked and no command}
  {line keyword settings are supported after the option; for use by remote}
  {invocation from a CGI script.}}
"-updateOnePackage" 4

 {{Same as -update, except only polls registered packages whose minPollPeriod}
  {has elapsed.  If package name is the special name "all", will poll all}
  {registered packages.}}
"-poll" 3

 {{Preview the following packages, either registered package names or '.nsb'}
  {files (local or at URLs), displaying which files are ready to be installed}
  {or removed.  Note that if you preview a '.nsb' file for a package that is}
  {not registered, you will not be prompted for installation choices so}
  {defaults will be used.}}
"-preview" 2

 {{Fetch all the following packages, either registered package names or '.nsb'}
  {files (local or at URLs), and verify that all files can be fetched and that}
  {the checksums match those that are in the '.nsb' files.  Each '.nsb' itself}
  {file will also be verified to be identical to the one referred to by the}
  {'nsbUrl' keyword in the file.  This is useful for maintainers of packages}
  {to test their packages without installing anything.}}
"-fetchAll" 2

 {{Audit registered packages to compare installed files with what the '.nsb'}
  {say should be installed.  The configuration keyword "auditOptions" controls}
  {the behavior of the audit.}}
"-audit" 3

 {{Remove the contents of the following registered packages, but do not remove}
  {them from the registry (see also -unregister).}}
"-remove" 2

 {{Remove the contents of the following registered packages if they are}
  {installed, and remove them from the registry.}}
"-unregister" 2

 {{Read path names from standard input and send the files in "multiget format"}
  {(a simple MIME-like protocol) to standard output.  Path names are relative}
  {to the the directory from which NSBD is invoked.  The optional parameter is}
  {a directory prefix to prepend to each path name.  This is intended to be}
  {used from a CGI script that is invoked with an http POST operation, to}
  {return files for the "multigetUrl" '.nsb' file keyword.  If the environment}
  {variable $CONTENT_LENGTH is set and non-empty (which it will be in a CGI}
  {that is invoked with http POST), at most that many bytes will be read from}
  {standard input.  Typical usage in a script is:}
  {    #!/bin/sh}
  {    cd top_directory; exec nsbd -multigetFiles "$QUERY_STRING"}
  {which will pass in any "?" parameter given at the end of the URL.  All}
  {paths (including the prefix) must be relative paths and strictly below the}
  {directory from which NSBD is invoked (that is, no ".." components are}
  {allowed).  Note: this is really a simple function that could be a program}
  {separate from NSBD, but it is a subset of -multigetPackage and it is easier}
  {to maintain here than as a separate program.}}
"-multigetFiles" 4

 {{This is similar to -multigetFiles except that files are read from where they}
  {have been installed by NSBD as part of a package.  This is intended for}
  {redistribution of packages.  The parameter is a registered package name.}
  {A typical usage in a CGI script is:}
  {    #!/bin/sh}
  {    NSBDPATH=~yourlogin/.nsbd; export NSBDPATH}
  {    exec nsbd executableTypes="$PATH_INFO" -multigetPackage "$QUERY_STRING"}
  {The CGI variable $PATH_INFO comes from the stuff in a URL immediately}
  {following a CGI script with a "/", and $QUERY_STRING comes from stuff}
  {following a "?" after that.  For example, the URL}
  {    http://any.com/cgi-bin/multiget/etype?pname}
  {gets a $PATH_INFO of /etype and a $QUERY_STRING of pname assuming multiget}
  {is a CGI script.  A leading slash on executableTypes is ignored here.}}
"-multigetPackage" 4
}
append optionList {
 {{Display list of paths that have changed for the following registered package}
  {compared to the '.nsb' file which is sent to standard input.  This is}
  {intended to be used from a remote CGI script (see supplied posttonsbd.sh)}
  {to return the list of files that should be sent to the -batchUpdate option.}
  {Note that, like anytime NSBD files are read from standard input, if the}
  {environment variable CONTENT_LENGTH is set and non-empty (which is standard}
  {on http POST operations to CGI scripts) then NSBD will read at most that}
  {many bytes.  The list of paths returned is preceeded by a line that has 5}
  {dashes, BEGIN CHANGED PATHS, and 5 dashes, and the list is followed by a}
  {line that has 5 dashes, END CHANGED PATHS, and 5 dashes.}}
"-changedPaths" 4

 {{Do a batched update of the following registered package.  Standard input is}
  {expected to contain a '.nsb' file, followed by a separator line that has 5}
  {dashes, BEGIN BATCH UPDATE, and 5 dashes, and by all of the changed files}
  {in the format used by the nsbd -multiget option.  This is intended to be}
  {used from a remote CGI script; see the README file that is supplied in the}
  {lib/nsbd directory for more information, particularly the discussion about}
  {posttonsbd.sh and pushpackage.sh.}}
"-batchUpdate" 4

 {{Update the comment template in all following files.  Files can be any of}
  {the recognized types of "NSBD" format files, but PGP signatures will be}
  {deleted from '.nsb' files.  Existing comments and unrecognized keywords}
  {will be deleted, and comments will be inserted for every valid keyword.}
  {The original file will be saved with "old" added to the beginning of the}
  {name.}}
"-updateComments" 2

 {{Do not put a PGP signature when creating a '.nsb' file from a '.npd' file.}
  {WARNING: Use carefully, only when your users can trust the network over}
  {which they retrieve your '.nsb' file.  This must be before the '.npd' file}
  {on the command line.}}
"-unsigned" 0

 {{Like -unsigned, but wait for a detached PGP signature file to appear with}
  {an extension '.nsb.sig' and then move the signature to the '.nsb' file.}
  {This is useful for people who have their PGP installed on a separate}
  {computer such as PC but run nsbd on a Unix server.}}
"-wait4signature" 0

 {{When creating a '.nsb' file from a '.npd' file, prompt the user for a reason}
  {for an update, to put into the "releaseNote" keyword in the '.nsb' file.}
  {Offer the opportunity to escape to the editor set in $EDITOR (default vi).}
  {Blank lines, indents, and lines beginning with '#' are ignored because of}
  {the '.nsb' file format rules.}}
"-askreason" 0

 {{When creating a '.nsb' file from a '.npd' file, automatically ignore files}
  {in the same way CVS and rsync --cvs-exclude do.  Unless an "excludePaths"}
  {also excludes .cvsignore files, they will be read for additional patterns}
  {to exclude for that current directory and all subsequent directories.}}
"-cvsExclude" 0

 {{Ignore PGP signature when processing a '.nsb' file.  WARNING: Use carefully,}
  {only when you can trust the source of the '.nsb' file.  This must be before}
  {the -update or -poll option on the command line.}}
"-ignoreSecurity" 0

 {{List package(s) that contain the given installed paths.  The paths must be}
  {complete paths: that is, the package "installTop" combined with the relative}
  {paths inside the packages.  The installTop part of the pattern is before %}
  {substitutions.  Note that the installTop part can be the empty string if}
  {installTop itself is empty, thus making all the patterns appear as relative}
  {paths.  As an optimization, if there is only one matching registered package}
  {or if the path exactly matches a registered validPath (that is, a validPath}
  {without glob wildcards), the package is listed without checking to see if}
  {there is actually an installed path that matches one of the expressions.}
  {The package names are printed on stdout.}}
"-getPathPackages" 3

 {{Like -getPathPackages except that only the registry is consulted; packages}
  {are never checked to see if a file is actually installed.}}
"-getPathRegisteredPackages" 3

 {{List the installed paths for given package(s) on stdout, relative to}
  {installTop.}}
"-getPackagePaths" 3

 {{List the registry database information for given package and key name on}
  {stdout.}}
"-getPackageRegistryKey" 3

 {{Invoke PGP to sign the given file, replacing its contents.  This has very}
  {little to do with the rest of NSBD but it is convenient for use in scripts}
  {that wish to modify '.nsb' files before they are signed (after creating them}
  {with -unsigned).}}
"-signFile" 1

 {{Retrieve text at given url and send it to standard output.  This is a}
  {general purpose command that has very little to do with the rest of NSBD,}
  {it is just here for convenience, especially for invoking a remote CGI}
  {script, and because it just takes one extra line of code to implement.}}
"-getUrl" 1

 {{Send standard input as an http POST command to the given url and send the}
  {result to standard output.  POST operations require the content length to}
  {be known up front, so that can be passed with a postLength=N command line}
  {variable; if the variable is not set, standard input will be copied into}
  {memory before it is sent.  As with -getUrl, this has very little to do with}
  {the operation of the rest of NSBD.}}
"-postUrl" 1

 {{Write all previously loaded registry files to the the specified output}
  {file.   Files to be loaded must be specified with registryFiles= on}
  {the command line.}}
"-dumpRegistry" 1

 {{Write all previously loaded config files to the the specified output}
  {file.   Files to be loaded must be specified with configFiles= on}
  {the command line.}}
"-dumpConfig" 1

}
catch {unset optionTable}
foreach {c k v} $optionList {
    foreach s $k {
	set optionTable($s) $v
    }
}

#
# Command-line help 
#

proc option-? {arg} {
    if {$arg == ""} {
	usage
    } else {
	option-help $arg
    }
}

proc option-help {arg {fd stdout}} {
    global optionList fileTitles
    if {$arg == "options"} {
	puts $fd "These are the available command-line options:"
	set options ""
	foreach {c s v} $optionList {
	    foreach opt $s {
		if {$c != ""} {
		    lappend options $opt
		}
	    }
	}
	display3Columns $fd $options
	puts $fd {For more help on an individual option use "-help -option_name"}
	puts $fd {  or for more help on all options use "-help alloptions".}
    } elseif {$arg == "keywords"} {
	puts $fd \
{Below are the available command line keywords, set by key=value
If the value is a list, it should be separated by commas.
Keyword settings can appear before or after a filename on the
   command line, but if the same keyword appears both before and
   after a filename, the one before takes precedence for that file.}
	foreach fileType {nsb npd cfg} {
	    upvar #0 ${fileType}Keys keys
	    puts $fd "For $fileTitles($fileType) files:" 
	    display3Columns $fd $keys
	}
	puts $fd {For more help on an individual keyword use "-help keyword_name"}
	puts $fd {  or for more help on all keywords use "-help allkeywords".}
    } elseif {$arg == "synopsis"} {
	puts $fd "Synopsis of nsbd usage:\n"
	puts $fd [nsbdSynopsis]
    } elseif {$arg == "operation"} {
	puts $fd "Operation of nsbd:\n"
	puts $fd [nsbdOperation]
    } elseif {$arg == "security"} {
	puts $fd "Security model of nsbd:\n"
	puts $fd [nsbdOperation]
    } elseif {$arg == "gettingstarted"} {
	puts $fd "Getting started with nsbd:\n"
	puts $fd [nsbdGettingStarted]
    } elseif {$arg == "fileformat"} {
	ensure-nsbdformat-loaded
	global nsbdFormatSpec
	puts $fd $nsbdFormatSpec
    } elseif {$arg == "examples"} {
	puts $fd "Examples of using nsbd:\n"
	puts $fd [nsbdExamples]
    } else {
	set gotone 0
	foreach fileType {nsb npd cfg nrd} {
	    upvar #0 ${fileType}Keylist keylist
	    if {$arg == "allkeywords"} {
		if {$fileType == "nrd"} {
		    continue
		}
		puts $fd "For $fileTitles($fileType) files:" 
	    }
	    foreach {c k v} $keylist {
		set lastk [lindex $k end]
		if {$lastk == $arg} {
		    puts $fd "For $fileTitles($fileType) files:" 
		}
		if {($lastk == $arg) || 
			(($arg == "allkeywords") && ([llength $k] == 1))} {
		    set gotone 1
		    set indent "  "
		    foreach word $k {
			puts $fd "$indent$word"
			set indent "$indent  "
		    }
		    if {$fileType == "npd"} {
			global nsbKeylist 
			foreach {c2 k2 v2} $nsbKeylist {
			    if {($k == $k2) && ($c == $c2)} {
				set c [list "Same as in $fileTitles(nsb) file."]
				break
			    }
			}
		    }
		    foreach l $c {
			puts $fd "$indent$l"
		    }
		}
	    }
	}
	foreach {c s v} $optionList {
	    if {([lsearch -exact $s $arg] >= 0) || ($arg == "alloptions")} {
		if {$c == ""} {
		    continue
		}
		set gotone 1
		puts $fd [join $s " or "]
		foreach l $c {
		    puts $fd "  $l"
		}
	    }
	}
	if {!$gotone} {
puts $fd \
{Please specify one of the following parameters to the -help option:
  "synopsis" - for a synopsis of nsbd usage.
  "operation" - for a general description of the operation of nsbd.
  "security" - for help on the security model of nsbd.
  "gettingstarted" - for help on getting started with nsbd.
  "options" - for a list of the available command line options.
  "alloptions" - for help on all available options.
  -option_name - for help on a specific option name.
  "keywords" - for a list of available command line keywords.
  "allkeywords" - for help on all available command line keywords.
  keyword_name - for help on a specific command line keyword, or any keyword
		    or subkeyword inside one of the four types of nsbd files.
  "fileformat" - for a detailed description of the format of nsbd files.
  "examples" - for examples of nsbd usage and files.}
	}
    }
    nsbdExit
}

#
# Display the items onto $fd in 3 columns, indented 4 spaces
#
proc display3Columns {fd items} {
    set is ""
    foreach i [lsort $items] {
	if {[llength $i] == 1} {
	    lappend is $i
	    if {[llength $is] == 3} {
		puts $fd [string trimright \
		    [format "    %-25s%-25s%-25s" [lindex $is 0] \
			[lindex $is 1] [lindex $is 2]]]
		set is ""
	    }
	}
    }
    if {[llength $is] > 0} {
	puts $fd [string trimright \
		    [format "    %-25s%-25s%-25s" [lindex $is 0] \
			[lindex $is 1] [lindex $is 2]]]
    }
}

#
# Print version number
#

proc option-V {} {
    option-version
}

proc option-version {} {
    puts [nsbdVersion]
    puts [tclVersion]
    puts [nsbdCopyright]
    nsbdExit
}

#
# Print the license
#

proc option-license {} {
    puts [getLicense]
    nsbdExit
}

#
# Process -register option
#

proc option-register {nsbfile} {
    global procNsbType
    if {$nsbfile == ""} {
	nsbderror "'.nsb' file or URL missing for -register option"
    }
    set procNsbType "register"
    set code [catch {startGui} string]
    if {$code == 1} {
	global cfgContents
	puts stderr \
"nsbd: Couldn't start Graphical User Interface; you can manually register
       for packages without one.  See nsbd -help gettingstarted."
	global errorInfo errorCode
	return -code $code -errorinfo $errorInfo -errorcode $errorCode $string
    }
    procfile $nsbfile "nsb"
}

#
# do procfile on nsbUrls from registered packages
#
# Look for a common nsbUrl for .nsb files and aggregate them
#   into a single fetch.
#

proc procnsbpackages {packages} {
    global procNsbType
    set batchList ""
    set batchTop ""
    set batchUrl ""
    set batchStoreDir ""
    foreach package $packages {
	foreach key {nsbUrl executableTypes} {
	    set $key [getCmdkey $key]
	    if {[set $key] == ""} {
		set $key [nrdLookup $package $key]
	    }
	}
	set version [getCmdkey version]
	if {$version == ""} {
	    set versions [nrdLookup $package versions]
	} else {
	    set versions [list $version]
	}
	set distributedPackageName [nrdLookup $package distributedPackageName]
	if {$distributedPackageName == ""} {
	    set distributedPackageName $package
	}
	if {$nsbUrl == ""} {
	    nsbderror "No nsbUrl registered for package $package"
	}
	set nsbUrls [substituteUrl $nsbUrl $package $executableTypes $versions]
	set top ""
	set storeDir ""
	set batchIt 0
	if {([llength $nsbUrls] == 1) && ($procNsbType != "fetchAll") &&
		(($batchUrl == "") || ($batchUrl == $nsbUrl)) &&
		    ($distributedPackageName == $package)} {
	    if {$executableTypes == ""} {
		set executableTypes [list ""]
	    }
	    if {$versions == ""} {
		set versions [list ""]
	    }
	    foreach executableType $executableTypes {
		foreach version $versions {
		    set ntop [getInstallTop $package $executableType $version]
		    if {$top == ""} {
			set top $ntop
		    } elseif {$top != $ntop} {
			# the installTops all have to be the same to batch
			set top ""
			break
		    }
		}
	    }
	    if {($top != "") && (($batchTop == "") || ($top == $batchTop))} {
		# executableType and version will be left set to the last
		#  one in the executableTypes and versions list, respectively
		set storeDir [file dirname \
		    [getNsbStoreName $package $executableType $version]]
		if {($batchStoreDir == "") || ($storeDir == $batchStoreDir)} {
		    set batchIt 1
		}
	    }
	}
	if {($batchList != "") && !$batchIt} {
	    #
	    # flush previously batched packages
	    #
	    donsbpackages $batchList $batchUrl $batchTop $batchStoreDir
	    set batchList ""
	}
	if {[llength $nsbUrls] > 1} {
	    #
	    # process each expanded nsbUrl separately
	    #
	    foreach url $nsbUrls {
		donsbpackages [list [list $package $url]] $nsbUrl $top $storeDir
	    }
	    continue
	}
	lappend batchList [list $package [lindex $nsbUrls 0]]
	set batchUrl $nsbUrl
	set batchTop $top
	set batchStoreDir $storeDir
    }

    if {$batchList != ""} {
	donsbpackages $batchList $batchUrl $batchTop $batchStoreDir
    }
}

#
# process a batch of nsb urls
# batchList is a list of {package subsitutedNsbUrl} pairs
# nsbUrl is the pre-substituted "nsbUrl" keyword
# installTop is the common installTop for the batch
# nsbStoreDir is the common directory that all the .nsb files are stored in
#
proc donsbpackages {batchList nsbUrl installTop nsbStoreDir} {
    #
    # when an http 1.1 client is available could also aggregate http
    #   but for now do only rsync
    # also, make sure that there is no per-package variation in $nsbUrl
    #   in the dirname level, because urlRsyncMultiCopy copies relative
    #   to the directory top
    #
    global procNsbType
    if {![regexp -nocase {^rsync://} $nsbUrl] ||
	    ([string first %P [file dirname $nsbUrl]] > 0) ||
		    ($procNsbType == "audit-update")} {
	foreach item $batchList {
	    foreach {package nsbUrl} $item {}
	    catchprocnsbpackage $nsbUrl $package
	}
	return
    }

    #
    # Copy all the .nsb files together in a batch
    #
    set installTmp [getInstallTmp $installTop]
    set tmpTop [file join $installTmp ".nsbfiles"]
    set paths ""
    foreach batch $batchList {
	foreach {package nsbUrl} $batch {}
	lappend paths [file tail $nsbUrl]
    }
    # $nsbUrl is now set to the last one found in the above loop

    # can't use [file dirname $nsbUrl] because it eliminates duplicate "/"
    set urlDir [string range $nsbUrl 0 [expr \
	{[string length $nsbUrl] - [string length [file tail $nsbUrl]] - 1}]]
    debugmsg "Rsyncing [llength $paths] files from $urlDir"
    debugmsg "  to $tmpTop, comparing to $nsbStoreDir"
    # the final "1" preserves timestamps, and files will not be
    #  copied if the sizes and timestamps match
    file mkdir $tmpTop
    urlRsyncMultiCopy $urlDir $tmpTop $paths $nsbStoreDir 1

    # if nsbStoreDir set, then rsync should have only copied an unchanged
    #  file because of a different time stamp; save the file with the
    #  correct timestamp so it won't need to be copied next time
    global saveUnchangedNsbfiles
    set saveUnchangedNsbfiles [expr {$nsbStoreDir != ""}]

    foreach batch $batchList {
	foreach {package nsbUrls} $batch {}
	foreach url $nsbUrls {
	    set url [lindex $nsbUrls 0]
	    set scratchName [file join $tmpTop [file tail $url]]
	    if {[file exists $scratchName]} {
		catchprocnsbpackage $url $package $scratchName
	    } else {
		progressmsg "No change in .nsb file for package $package"
	    }
	}
    }
    set saveUnchangedNsbfiles 0

    # only delete the $tmpTop directory and its parent if they are empty
    catch {file delete $tmpTop $installTmp}
}


#
# Catch errors when processing a package
#
proc catchprocnsbpackage {url package {scratchName ""}} {
    global procNsbType
    if {($procNsbType == "poll") || ($procNsbType == "update") || \
		($procNsbType == "audit-update")} {
	if {$procNsbType == "poll"} {
	    nrdUpdate $package set lastTimePolled [currentTime]
	}
	set code [catch {procfile $url "nsb" $package $scratchName} message]
    } else {
	set code 0
	procfile $url "nsb" $package $scratchName
    }
    if {$code > 0} {
	global errorInfo errorCode
	if {$errorCode != "NSBD INTERNAL"} {
	    # escalate the error
	    error $message $errorInfo $errorCode
	}
	#
	# else continue to update the next package
	#
	nonfatalerror "Error processing package $package:\n  $message"
	nrdAbortUpdates
    } else {
	if {$scratchName != ""} {
	    # suceeded but the scratch file may have been left
	    #   if there was no change
	    file delete $scratchName
	}
	# in case it hadn't been done already; no effect if it had
	nrdCommitUpdates
    }
}

#
# expand a packages list of "all" or registered packages
#

proc expandRegisteredPackages {packages opt} {
    if {$packages == ""} {
	nsbderror "package name(s) or \"all\" missing for $opt option"
    }
    set dopackages ""
    foreach package $packages {
	if {$package == "all"} {
	    return [nrdPackages]
	} else {
	    if {![nrdPackageRegistered $package]} {
		nonfatalerror "\"$package\" not registered; \"$opt\" requires registered package"
	    } else {
		lappend dopackages $package
	    }
	}
    }
    return $dopackages
}

#
# Process -update option
#

proc option-update {packages} {
    global procNsbType
    set procNsbType "update"
    procnsbpackages [expandRegisteredPackages $packages "-update"]
}

proc option-updateOnePackage {package} {
    if {$package == ""} {
	nsbderror "Package name not given"
    }
    option-update [list $package]
}

#
# Process -poll option
#
proc option-poll {packages} {
    global cfgContents procNsbType
    set procNsbType "poll"
    set dopackages ""
    foreach package [expandRegisteredPackages $packages "-poll"] {
	set minPollPeriod [nrdLookup $package "minPollPeriod"]
	if {$minPollPeriod == ""} {
	    if {[info exists cfgContents(minPollPeriod)]} {
		set minPollPeriod $cfgContents(minPollPeriod)
	    } else {
		set minPollPeriod "1d"
	    }
	}
	set number 0
	set unit "d"
	scan $minPollPeriod "%d%s" number unit
	if {$number == 0} {
	    progressmsg "Package $package is never polled"
	    continue
	}
	set lastTimePolled [nrdLookup $package lastTimePolled]
	if {$lastTimePolled != ""} {
	    set multiplier 0
	    switch -regexp $unit {
		m|M {set multiplier 60}
		h|H {set multiplier [expr {60 * 60}]}
		d|D {set multiplier [expr {60 * 60 * 24}]}
		w|W {set multiplier [expr {60 * 60 * 24 * 7}]}
		default {
		    nsbderror \
"minPollPeriod for package $package ($minPollPeriod)
  must have units of m, h, d, or w"
		}
	    }
	    set number [expr {round($number * $multiplier * 0.98)}]
	    set nextTime [httpTime [expr {[scanAnyTime $lastTimePolled] + $number}]]
	    if {[compareTimes [currentTime] $nextTime] < 0} {
		updatemsg "Poll time for package $package not yet arrived: $nextTime"
		continue
	    }
	}
	lappend dopackages $package
    }
    procnsbpackages $dopackages
}

#
# Process -preview option
#

proc option-preview {arg} {
    global procNsbType
    if {$arg == ""} {
	nsbderror "'.nsb' file or URL or package name missing for -preview option"
    }
    set procNsbType "preview"
    if {[nrdPackageRegistered $arg]} {
	procnsbpackages [list $arg]
    } else {
	procfile $arg "nsb"
    }
}

#
# Process -fetchAll option
#

proc option-fetchAll {arg} {
    global procNsbType
    if {$arg == ""} {
	nsbderror "'.nsb' file or URL or package name missing for -fetchAll option"
    }
    set procNsbType "fetchAll"
    if {[nrdPackageRegistered $arg]} {
	procnsbpackages [list $arg]
    } else {
	procfile $arg "nsb"
    }
}

#
# Process -audit option
#
proc option-audit {packages} {
    auditpackages $packages
}

#
# Process -remove option
#
proc option-remove {arg} {
    if {![nrdPackageRegistered $arg]} {
	nsbderror "\"$arg\" not registered; -remove requires registered package"
    }
    global procNsbType
    set procNsbType "remove"
    bypassProcNsb $arg
    nrdCommitUpdates
}

#
# Process -unregister option
#
proc option-unregister {arg} {
    if {![nrdPackageRegistered $arg]} {
	nsbderror "\"$arg\" not registered; -unregister requires registered package"
    }
    option-remove $arg
    nrdUpdate $arg deletePackage "" ""
    nrdCommitUpdates
    updatemsg "Unregistered package $arg"
}

#
# Process -multigetFiles and -multigetPackage options
#

proc option-multigetFiles {arg} {
    option-multiget files $arg
    # exit here because this is an infoOnlyOption
    nsbdExit
}

proc option-multigetPackage {arg} {
    option-multiget package $arg
}

proc option-multiget {gettype arg} {
    global procNsbType cfgContents env

    set procNsbType "multiget"
    # setting a negative verbose level prevents the "errormsg" command from
    #   printing to stderr at all; errors are handled as a special case instead
    set cfgContents(verbose) -1

    if {$gettype == "files"} {
	# also disable log messages because we've skipped locating the
	#  configuration file
	set cfgContents(logLevel) -1

	set prefix $arg
    } elseif {$gettype != "package"} {
	nsbderror "internal error; gettype not files or package"
    } else {
	set package $arg

	if {$package == ""} {
	    nsbderror "package name missing for -multigetPackage option"
	}
	if {![nrdPackageRegistered $package]} {
	    nsbderror "\"$package\" not registered; -multigetPackage requires registered package"
	}

	#
	# figure out everything it takes to apply substitutions
	#

	set executableTypes [getCmdkey executableTypes]
	if {[string index $executableTypes 0] == "/"} {
	    # remove leading slash from a $PATH_INFO
	    set executableTypes [string range $executableTypes 1 end]
	}
	if {$executableTypes == ""} {
	    set executableTypes [nrdLookup $package executableTypes]
	}
	set version [getCmdkey version]
	if {$version == ""} {
	    set versions [nrdLookup $package versions]
	} else {
	    set versions [list $version]
	}

	set nsbStoreFiles [findNsbStoreFiles $package $executableTypes]
	if {[llength $nsbStoreFiles] < 1} {
	    nsbderror "can't find any stored '.nsb' files for package $package\n    with executableTypes $executableTypes"
	}
	if {[llength $nsbStoreFiles] > 1} {
	    nsbderror "more than one stored '.nsb' file for package $package\n    with executableTypes $executableTypes"
	}
	set nsbStoreFile [lindex $nsbStoreFiles 0]

	nsbdParseFile $nsbStoreFile "nsb" contents

	initPathSubstitutions $package contents $executableTypes $versions

	# Since only one '.nsb' file is allowed, if the paths to stored nsb
	#   files contain %E or %V there must be exactly one in the
	#   executableTypes or versions arguments respectively.  We cannot
	#   have fewer nsbfiles than installTops, so we can safely take the
	#   first one of each when getting installTop.

	set installTop [getInstallTop $package [lindex $executableTypes 0] \
						[lindex $versions 0]]
    }

    puts "Content-Type: application/x-multiget\n"

    foreach path [split [expr {([info exists env(CONTENT_LENGTH)] &&
				    ($env(CONTENT_LENGTH) != "")) ?
				[read stdin $env(CONTENT_LENGTH)] :
				[read stdin]}] "\n"] {
	if {$path == ""} {
	    continue
	}
	if {$gettype == "files"} {
	    set fullPath [file join $prefix $path]
	    set checkPath $fullPath
	} else {
	    set fullPath [file join $installTop [lindex [substitutePath $path] 1]]
	    set checkPath $path
	}
	if {[set msg [relativePathCheck $checkPath]] != ""} {
	    nsbderror $msg
	}

	withOpen fd $fullPath "r" {
	    file stat $fullPath statb
	    if {$statb(type) != "file"} {
		nsbderror "$fullPath is not a file"
	    }
	    puts "Content-Name: $path"
	    puts "Content-Length: $statb(size)\n"
	    fconfigure $fd -translation binary
	    set stdoutConfig [fconfigure stdout -translation]
	    fconfigure stdout -translation binary
	    fcopy $fd stdout
	    fconfigure stdout -translation $stdoutConfig
	}
	puts ""
    }
}


#
# Process -changedPaths option
#

proc option-changedPaths {arg} {
    global procNsbType
    if {$arg == ""} {
	nsbderror "package name missing for -changedPaths option"
    }
    if {![nrdPackageRegistered $arg]} {
	nsbderror "\"$arg\" not registered; -changedPaths requires registered package"
    }

    # don't need to check signatures because nothing is being updated
    option-ignoreSecurity

    set procNsbType "changedPaths"
    procfile - "nsb" $arg
}

#
# Process -batchUpdate option
#

proc option-batchUpdate {arg} {
    global procNsbType
    if {$arg == ""} {
	nsbderror "package name missing for -batchUpdate option"
    }
    if {![nrdPackageRegistered $arg]} {
	nsbderror "\"$arg\" not registered; -batchUpdate requires registered package"
    }
    set procNsbType "batchUpdate"
    procfile "-" "nsb" $arg
}

#
# Process -ignoreSecurity option
#
proc option-ignoreSecurity {} {
    global ignoreSecurity
    set ignoreSecurity 1
}

#
# Process -unsigned option
#
proc option-unsigned {} {
    global unsignedNsbfiles
    set unsignedNsbfiles 1
}

#
# Process -wait4signature option
#
proc option-wait4signature {} {
    global unsignedNsbfiles
    set unsignedNsbfiles 2
}

#
# Process -askreason option
#
proc option-askreason {} {
    global askReason
    set askReason 1
}

#
# Add cvsExclude patterns to the global list.  If the optional second parameter
# is non-empty, only add the patterns for that directory, otherwise add it
# for all directories.
#

proc addCvsExcludePats {patterns {fordir ""}} {
    global cvsExcludePats
    foreach pattern $patterns {
	if {$fordir != ""} {
	    set pattern "$fordir/$pattern"
	}
	luniqueAppend cvsExcludePats $pattern
	if {($fordir == "") && ([string index $pattern 0] != "*")} {
	    debugmsg "Adding CVS exclude patterns $pattern and */$pattern"
	    lappend cvsExcludePats "*/$pattern"
	} else {
	    debugmsg "Adding CVS exclude pattern $pattern"
	}
    }
}

#
# Add contents of a .cvsignore file to the exclude patterns if it exists in dir
# unless it is excluded by an excludePaths.  If the optional second parameter
# is non-empty, only add the patterns for that directory, otherwise add it
# for all directories.
#
proc addCvsIgnore {dir {fordir ""}} {
    global cvsExclude
    if {![info exists cvsExclude]} {
	return
    }
    upvar npdContents npdContents
    set path "$dir/.cvsignore"
    if {[pathExcluded $path] == 1} {
	return
    }
    if {[file exists $path]} {
	debugmsg "Adding CVS excludes from [cleanPath $path]"
	withOpen fd $path "r" {
	    addCvsExcludePats "[read $fd]" [cleanPath $fordir]
	}
    }
}

#
# Initial list of CVS exclude patterns
#
# 7/23/03 PSF added *.olb and *.exe to match list in 
# http://www.cvshome.org/docs/manual/cvs-1.11.6/cvs_18.html#SEC175
#
set initCvsExcludePats {
    RCS SCCS CVS CVS.adm RCSLOG cvslog.*
    tags TAGS .make.state .nse_depinfo
    *~ #* .#* ,* *.old *.bak *.BAK *.orig
    *.rej .del-* *.a *.olb *.o *.obj *.so *.exe *.Z *.elc *.ln
    core .cvsignore
}
#
# Process -cvsExclude option
#
proc option-cvsExclude {} {
    global cvsExclude cvsExcludePats initCvsExcludePats env

    set cvsExclude 1

    addCvsExcludePats $initCvsExcludePats

    addCvsIgnore "~"

    if {[info exists env(CVSIGNORE)]} {
	debugmsg "Adding CVS excludes from \$CVSIGNORE"
	addCvsExcludePats $env(CVSIGNORE)
    }
}

#
# Process -updateComments option
#
proc option-updateComments {fileName} {
    if {$fileName == ""} {
	usage {-updateComments requires a file name parameter}
    }
    progressmsg "Updating comments in $fileName"
    set fileType [lindex [nsbdParseFile $fileName "" contents] 0]
    set scratchName [scratchAddName "tem"]
    withOpen fd $scratchName "w" {
	nsbdGenTemplate $fd $fileType contents
    }
    set oldName [addFilePrefix $fileName old]
    notrace {file rename -force $fileName $oldName}
    notrace {file rename $scratchName $fileName}
    progressmsg "Old file saved in $oldName"
}


#
# Process -getPathPackages option
#
proc option-getPathPackages {paths} {

    applyCmdkeys cmdContents nsb
    if {[getCmdkey verbose cfg] == ""} {
	# default to verbose level 0 if verbose not set
	global cfgContents
	set cfgContents(verbose) 0
    }

    set packages ""
    foreach path $paths {
	set answers [findMatchingPackages $path]

	if {$answers == ""} {
	    # no matches
	    continue
	}
	if {[llength $answers] == 1} {
	    # only one package matched
	    lappend packages [lindex [lindex $answers 0] 0]
	    continue
	}
	set gotone 0
	foreach answer $answers {
	    if {[lindex $answer 1]} {
		# the package was selected by a non-wildcard validPath
		#  (that is, the path was an exact match); no need to
		#  look inside
		lappend packages [lindex $answer 0]
		set gotone 1
	    }
	}
	if {$gotone} {
	    continue
	}

	#
	# Matched more than one package by wildcard, need to look inside
	#   the packages for a match
	#
	foreach answer $answers {
	    set package [lindex $answer 0]
	    set gotone 0
	    set executableTypes [getExecutableTypes $package cmdContents 1]
	    set versions [getVersions $package cmdContents]
	    # as a side effect calculateInstallTops sets a topNsbStoreNames
	    #  indexed by the installTops, and storeExecutableTypes and
	    #  storeVersions indexed by the topNsbStoreNames
	    set installTops \
		[calculateInstallTops $package $executableTypes $versions]
	    foreach installTop $installTops {
		foreach nsbStoreName $topNsbStoreNames($installTop) {
		    loadOldNsbFile 1 $nsbStoreName $package \
			    $storeExecutableTypes($nsbStoreName) \
			    $storeVersions($nsbStoreName)
		    if {![info exists oldnupContents(paths)]} {
			continue
		    }
		    # Look through the substituted paths for a match
		    #   with the patterns
		    foreach otherPath $oldnupContents(paths) {
			if {$path == $otherPath} {
			    lappend packages $package
			    set gotone 1
			    break
			}
		    }
		    if {$gotone} {
			break
		    }
		}
		if {$gotone} {
		    break
		}
	    }
	}
    }
    puts [join [lsortUnique $packages] "\n"]
}

#
# Process -getPathRegisteredPackages option
#
proc option-getPathRegisteredPackages {paths} {

    set packages ""
    foreach path $paths {
	foreach answer [findMatchingPackages $path] {
	    lappend packages [lindex $answer 0]
	}
    }
    puts [join [lsortUnique $packages] "\n"]
}

#
# Process -getPackagePaths option
#
proc option-getPackagePaths {packages} {
    applyCmdkeys cmdContents nsb
    if {[getCmdkey verbose cfg] == ""} {
	global cfgContents
	set cfgContents(verbose) 0
    }

    foreach package $packages {
	if {![nrdPackageRegistered $package]} {
	    nonfatalerror "\"$package\" not registered; \"-getPackagePaths\" requires registered package"
	    continue
	}
	set executableTypes [getExecutableTypes $package cmdContents 1]
	set versions [getVersions $package cmdContents]
	# as a side effect calculateInstallTops sets a topNsbStoreNames
	#  indexed by the installTops, and storeExecutableTypes and
	#  storeVersions indexed by the topNsbStoreNames
	set installTops \
	    [calculateInstallTops $package $executableTypes $versions]
	foreach installTop $installTops {
	    foreach nsbStoreName $topNsbStoreNames($installTop) {
		loadOldNsbFile 1 $nsbStoreName $package \
			$storeExecutableTypes($nsbStoreName) \
			$storeVersions($nsbStoreName)
		if {![info exists oldnupContents(paths)]} {
		    continue
		}
		foreach path $oldnupContents(paths) {
		    puts $path
		}
	    }
	}
    }
}

#
# Process -getPackageRegistryKey option
#
proc option-getPackageRegistryKey {packageandkey} {
    if {[llength $packageandkey] != 2} {
	nsbderror "wrong number of parameters: -getPackageRegistryKey expect package and key"
    }
    set package [lindex $packageandkey 0]
    set key [lindex $packageandkey 1]
    global nrdKeytable
    if {![info exists "nrdKeytable(packages $key)"]} {
	nsbderror "\"$key\" is not a valid registry key name"
    }
    if {![nrdPackageRegistered $package]} {
	nsbderror "\"$package\" not registered; \"-getPackageRegistryKey\" requires registered package"
    }

    set answer [nrdLookup $package $key]
    if {$answer != ""} {
	if {"$nrdKeytable(packages $key)"} {
	    foreach item $answer {
		puts $item
	    }
	} else {
	    puts $answer
	}
    }
}

#
# Process -signFile option
#
proc option-signFile {file} {
    if {![file writable $file]} {
	nsbderror "$file does not exist or is not writable"
    }

    pgpSignFile $file $file
}

#
# Process -getUrl option
#
proc option-getUrl {url} {
    urlCopy $url -
}

#
# Process -postUrl option
#
proc option-postUrl {url} {
    global cfgContents
    if {[info exists cfgContents(postLength)]} {
	urlCopy $url - "" "-querychannel stdin \
			   -querylength $cfgContents(postLength) \
			   -queryprogress urlProgress"
    } else {
	urlCopy $url - "" {-query [read stdin]}
    }
}

#
# Process -dumpConfig option
#
proc option-dumpConfig {outf} {

    global cfgContents

    # We don't want the config file list includeed in the output file
    if [info exists cfgContents(configFiles)] {
	unset cfgContents(configFiles)
    }

    foreach configFile [getCmdkey configFiles cfg] {
	procfile $configFile cfg
    }

    nsbdGenFile $outf cfg cfgContents

    exit
}

#
# Process -dumpRegistry option
#
proc option-dumpRegistry {outf} {

    global nrdContents 

    foreach registryFile [getCmdkey registryFiles cfg] {
	procfile $registryFile nrd
    }

    nsbdGenFile $outf nrd nrdContents
	
    exit
}

