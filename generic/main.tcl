#
# Main part of NSBD program.  Includes initialization, parsing of the
#  command line, basic processing of the different types of files that
#  NSBD works with, and handling of temporary files.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 18 Nov 1996
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

proc nsbdCopyright {} {
return \
{Not-So-Bad Distribution   Copyright 1996-2003
Automated Distribution especially for Open Source Software
Maintained by the Lucent Central Exptools Administrator <exptools@lucent.com>
NSBD home page: http://www.bell-labs.com/nsbd
This is free software, and you are welcome to redistribute it under the terms
of the GNU General Public License.  NSBD comes with absolutely no warranty.
Use the "-license" option for details of the license and the non-warranty.
Bell Labs, Innovations for Lucent Technologies}
}

proc tclVersion {} {
return "Using Tcl patchlevel [info patchlevel]"
}

proc usage {{reason ""}} {
    if {$reason != ""} {
	puts stderr "nsbd: $reason"
    }
    puts stderr "[nsbdVersion]\n[tclVersion]\n[nsbdCopyright]\n[nsbdSynopsis]"
    # return magic errorCode, avoids printing error message
    error "" "" "NSBD SILENT"
}

proc nsbdSynopsis {} {
return \
{nsbd {-help | -?} [topic]
nsbd {-version | -V | -license}
nsbd [*] [-unsigned|-wait4signature] [-askreason] [-cvsExclude] [*] {file.npd|-}
nsbd [**] -register {URL | file.nsb | -}
nsbd [**] {-update | -poll | -audit} {all | {[*] package [...]}}
nsbd [**] {-preview | -fetchAll} {[*] {package | URL | file.nsb | -}} [...]
nsbd [*] {-remove | -unregister} {[*] package [...]}
nsbd {{-multigetFiles [directoryPrefix]} | {[*] -multigetPackage package}}
nsbd [**] {-updateOnePackage | -changedPaths | -batchUpdate} package
nsbd [*] -updateComments {file.ncf | file.nrd | file.npd | file.nsb}
nsbd [*] {-getPathPackages | -getRegisteredPathPackages} glob_pattern [...]
nsbd [*] -getPackagePaths package [....] 
nsbd [*] -getPackageRegistryKey package key
nsbd {-signFile file} | {-getUrl URL} | {-postUrl URL}
nsbd registryFiles=infile.nrd[,...] -dumpRegistry outfile.nrd
nsbd configFiles=infile.ncf[,...] -dumpConfig outfile.ncf
[*] indicates any keyword=value.
[**] indicates same plus "-ignoreSecurity".
"-" indicates standard input.}
}

proc nsbdOperation {} {
return \
{NSBD, Not-So-Bad Distribution, is an automated distribution system that is
designed for distributing open source software on the internet, where users
cannot trust the network and cannot entirely trust the maintainers of
software.  NSBD authenticates packages with GNU Privacy Guard (GnuPG) or
"Pretty Good(Tm) Privacy" (PGP(Tm)) digital signatures so users can be
assured that packages have not been tampered with, and it limits the
maintainer to only update selected files and directories on the user's
computer.  NSBD's focus is on security, leaving as much control as is
practical in the users' hands.

To accomplish the automated updates, NSBD supplies a means of checking for
updates to packages and automatically downloading and installing the updates.
This "automated pull" style of distribution has the same effect as the
"push" style of distribution that is being given press lately, but gives
more control to the user.  A direct "push" style is also supported which is
not used as frequently but which is especially appropriate for situations
where there are multiple contributors to a shared server (for example, a
shared web-page server).  NSBD can "pull" directly over http or by using
rsync to minimize network usage.

This is the basic operation: maintainers of packages make their files
available at some http or ftp URL, create a Nsbd Package Description '.npd'
file to describe the files, and run NSBD interactively with that '.npd'
file to indicate that they have approved the files.  That step creates a
Not-So-Bad '.nsb' file which contains the URLs for all files in the
package, MD5 or SHA1 message digests for each file (also known as secure
hashes; they're like checksums, only with much better security because it
is computationally infeasible to discover different file content to match
an existing message digest), and a digital signature of the whole file
created by PGP or GPG.  The maintainer then makes the '.nsb' file also
available at a URL with a MIME Content-type of "application/x-nsbd".

When a user clicks on a hyperlink to the URL of a '.nsb' file in his or her
web browser, the '.mailcap' file of the web browser will invoke NSBD with
the '-register' option which pops up a window from which the package can be
registered and installed.  Then, the user runs 'nsbd -poll' periodically
(such as from cron) to check for changes to the '.nsb' file.  If the
signature has changed and is valid, the files whose message digest
information has changed will be loaded.  If all the loaded files match the
message digest information, they will be installed where the user wants
them, and files that have been removed from the package will be removed
from the user's copy.  The user is thus assured that no matter how insecure
the network, only updates from the authorized maintainer will be
automatically installed because only the authorized maintainer controls the
PGP or GPG private key.  The user is also assured that if multiple files
have changed they will be installed all together or not at all.  (Detail
note:  in order to be valid, the timestamp on a '.nsb' file has to be newer
than the timestamp on the previous one, to avoid the unlikely case of a
spoofer installing an old valid '.nsb' file in a "replay attack").

Alternatively, if only a small number of users (typically one) are expected
for a package, users may permit maintainers of packages to directly "push"
package updates as opposed to the "automated pull" of 'nsbd -poll'.  To use
this mode of operation, the user(s) install supplied CGI scripts and the
maintainers invoke them to directly send in updates rather than making the
package available at a URL (see the -batchUpdate option).  The same
security model applies in either mode of operation.

By using the included program breloc, NSBD can also relocate binary
packages so they can be installed at a location of the user's choice, if
the binary packages are configured with a "prefix" that has a sufficient
number of trailing slashes to accomodate the user's chosen location.}
}

proc nsbdSecurityModel {} {
return \
{The fundamental security model of NSBD is that the user retains control
and only gives away as much authority as necessary to get the update job
done but no more.  Only authenticated updates from authorized maintainers
are accepted, files are only installed into authorized locations on the
user's disk, and only authorized commands are run during installation.
Maintainers may include in their package suggested values for all of the
installation parameters, but it is up to the user to accept them.
Alternatively, users may selectively give away additional privileges to
maintainers to allow them to remotely update most of the installation
parameters, depending on how much they trust the maintainers (see
"maintainerUpdatableKeys").

These are the installation parameters related to security for each package;
see also the descriptions of each keyword in the different NSBD files:
  1. maintainers - the list of PGP/GPG user ids of authorized maintainers
       that may install updates.
  2. installTop - the top level directory in which to install files into.
       No complete paths or ".." components are allowed in installed paths,
       so all files will be strictly below this directory. 
  3. validPaths - list of files and directories underneath installTop that
       may be written.
  4. preUpdateCommands/postUpdateCommands - arbitrary commands to execute
       before and after installation of an update.
If the maintainer suggests values for any of these parameters, users of
packages need to realize that the packages may not work properly if they
decide to set the parameters to something else.

Note that if executable programs are distributed and the user executes
those programs after installation is complete, that program will have all
the same access privileges that the user has.  However, if installation is
done under a privileged user id or on a trusted server which don't execute
the programs themselves, the users can at least trust that the programs
won't interfere with each other.  For example, if an untrustworthy
maintainer is trusted to install an infrequently-used program, users can at
assume that other programs installed under the same privileged user id will
not be tainted by the bad program.

Another important part of the security model is that it is designed to be
useful for redistribution.   For example, Bell Labs has a redistribution
system called "Exptools" in which individuals around the company are
permitted to install packages onto the master copy of the distribution
system.  From there, the packages are distributed to a large number of
servers.  The NSBD ".nsb" files, on which the original maintainers have
manually applied digital signatures authorizing all files in their
packages, are intended to be redistributed along with the packages to
verify authenticity on each end server.  These signatures guarantee that,
even if someone breaks into a server and tampers with distributed files,
the non-authorized files will never be distributed any futher.}
}

proc nsbdGettingStarted {} {
return \
{When you run nsbd the first time, it will create ~/.nsbd/config.ncf and
~/.nsbd/registry.nrd for you and will ask you where your PGP or GPG is and
if you want to auto register for NSBD binary updates.  It will also ask you
if you want it to add a line to your $HOME/.mailcap of the form

    application/x-nsbd; $HOME/nsbd/bin/nsbd -register %s

to be used for launching nsbd from a web browser to register for packages.

If you are only a user of packages and not a maintainer, you don't need to
worry about most keywords and you can completely ignore the '.npd' and
'.nsb' files.  You should just peruse the configuration file keywords to
see if some of them seem useful to you.  Almost all the keywords in the
Registry Database are filled in from the window that pops up when you
register a package with -register, and you should probably try to understand
most of those (there is also pop-up help for those). 

If you are a maintainer of packages, you will need to understand the
keywords in the '.npd' files.  To create a template package description
file with a comment for each keyword, create a new '.npd' file with the
line "nsbPackageDescription: 1" and run "nsbd -updateComments" on the
file.  If you want to make your package available on the web, you should
also look at the lib/nsbd directory for some helpful CGI scripts you may
want to use.

Most people won't need to learn about the '.nsb' files unless they are
trying to evaluate the security of the NSBD protocol.

Note that only the -register option uses a Graphical User Interface; all other
operations are from the command line.  If you do not have a GUI display
available, you can manually register a package by editting registry.nrd and
filling in information from the '.nsb' file (which you can retrieve with
-getUrl) and then using the -update option.  The most important information
from the '.nsb' file are the keywords packageName, nsbUrl, maintainers, and
validPaths (the latter is normally computed from paths).  You will also
need to manually add any needed PGP or GPG keys.}
}

proc nsbdExamples {} {
return \
{Here's a sample package description file for the nsbd binary
package, "nsbd.npd":
  # every .npd file has to begin with the following line
  nsbPackageDescription: 1
  maintainers:
    Lucent Central Exptools Administrator <exptools@lucent.com>
      pgpKeyUrl: http://www.bell-labs.com/project/wwexptools/keys/exptools.txt
  executableTypes: sparc-sun-solaris,mips-sgi-irix
  nsbUrl: http://www.bell-labs.com/project/nsbd/%P.nsb
  topUrl: http://www.bell-labs.com/project/nsbd/binaries
  regSubs:
    # delete all .%E suffixes when installing
    \.%E$
  paths:
    # %E expands to every executableType
    bin/nsbd.%E
    lib/nsbd/
    man/man1/nsbd.1

To update the file to include complete comments for each available
keyword:
  nsbd -updateComments nsbd.npd

To create the '.nsb' file from the package description:
  nsbd nsbd.npd

To register for the package via a GUI:
  nsbd -register http://www.bell-labs.com/project/nsbd/%P.nsb

To poll for and install updates for all packages, good to do from
cron nightly or weekly:
  nsbd -poll all

To manually register for the nsbd solaris binary package, add this
to ~/.nsbd/registry.nrd:
  packages:
    nsbd
      nsbUrl:
        http://www.bell-labs.com/project/nsbd/nsbd.nsb
      maintainers:
        Lucent Central Exptools Administrator <exptools@lucent.com>
      executableTypes:
        sparc-sun-solaris
      validPaths:
        bin/nsbd
        lib/nsbd/
        man/man1/nsbd.1

To automatically make and install after an update to nsbd source,
add this to ~/.nsbd/registry.nrd:
  packages:
    nsbdsrc
      postUpdateCommands:
        cd ~/src/nsbd/unix;configure --prefix ~/nsbd;make install #
The  ending '#' is to ignore the parameter of the name of a file containing
a description of the update.}
}


#
# This is for versions before tcl8.0
#
if {([info commands "unsupported0"] == "unsupported0") &&
		([info commands "fcopy"] != "fcopy")} {
    proc fcopy {input output args} {
	if {[lindex $args 0] == "-size"} {
	    unsupported0 $input $output [lindex $args 1]
	} else {
	    unsupported0 $input $output
	}
    }
}

proc nsbd {args} {
    global nsbdExitCode
    set code [catch {
	eval nsbdDoit $args
    } string]
    nsbdExitCleanup
    if {$code == 1} {
	nsbdErrorHandler $string
    }
    return [expr $code + $nsbdExitCode]
}

#
# Top-level handler for errors in nsbd program
#
proc nsbdErrorHandler {err} {
    global procNsbType errorCode errorInfo guiStarted
    if {$errorCode == "NSBD SILENT"} {
	return
    }
    errormsg $err
    if {$procNsbType == "multiget"} {
	fconfigure stdout -translation crlf
	regsub -all "\n\[ \t\n\]*" $err " " oneLineErr
	puts "X-Multiget-Error: $oneLineErr"
	puts "Content-Type: text/plain"
	puts ""
	puts "Error from nsbd:\n  $err"
	if {$errorCode != "NSBD INTERNAL"} {
	    puts "Stack trace:\n[indent2 $errorInfo]"
	}
    } elseif {$guiStarted} {
	set msg "Error: $err"
	set savErrorInfo $errorInfo
	if {[tk_dialog .tkerror "Error in NSBD" $msg error 0 \
						"Exit" "Stack Trace"] == 1} {
	    append msg "\n\nFirst part of stack trace:"
	    set nlines 0
	    foreach line [split $savErrorInfo "\n"] {
		append msg "\n$line"
		if {[incr nlines] > 15} {
		    break
		}
	    }
	    if {[tk_dialog .tkerror "Error in NSBD" $msg error 0 \
				    "Exit" "Full trace to stderr"] == 1} {
		puts stderr "Stack trace:\n$savErrorInfo"
	    }
	}
    } elseif {([set verboseLevel [verboseLevel]] >= 7) || 
			    		($errorCode != "NSBD INTERNAL")} {
	if {$verboseLevel >= 7} {
	    debugmsg "Stack trace:\n[indent2 $errorInfo]"
	} else {
	    noticemsg "First part of stack trace (for more use verbose=7):"
	    set nlines 0
	    foreach line [split $errorInfo "\n"] {
		noticemsg "  $line"
		if {[incr nlines] > 15} {
		    break
		}
	    }
	}
    }
}

#
# Handler for an error while running tk
#
proc tkerror {err} {
    # make sure guiStarted is set -- there are some race
    #  conditions where it might have not been
    global guiStarted
    set guiStarted 1
    nsbdErrorHandler $err
    nsbdExitCleanup
    exit 1
}

#
# Clean up before doing direct exit
#
proc nsbdExit {{code 0}} {
    nsbdExitCleanup
    exit $code
}

#
# Things to do to clean up.  This is also called directly from
#  Unix signal handlers.  Save errorInfo/errorCode, because this is
#  often called from error handlers that later want to print out stack.
#
proc nsbdExitCleanup {} {
    global errorInfo errorCode
    set savErrorInfo $errorInfo
    set savErrorCode $errorCode
    scratchClean
    set errorInfo $savErrorInfo
    set errorCode $savErrorCode
}

#
# Raise an nsbd-internal error, one which does not cause a stack trace
#
proc nsbderror {message} {
    error $message "" "NSBD INTERNAL"
}

#
# Print an error message and continue, keeping track of number of errors
#
proc nonfatalerror {message} {
    global nsbdExitCode errorCode
    incr nsbdExitCode
    set errorCode "NSBD INTERNAL"
    nsbdErrorHandler $message
}

#
# Turn any error in body into an nsbd-internal error
#
proc notrace {body} {
    set code [catch {uplevel $body} string]
    if {$code == 1} {
	global errorInfo
	return -code $code -errorinfo $errorInfo -errorcode "NSBD INTERNAL" $string
    }
    return -code $code $string
}

#
# Initialize nsbd and process command line arguments.  nsbd may be run
#  multiple times from within tclsh, so re-initialize anything that may
#  be left over from a previous run
#
proc nsbdDoit {args} {
    global nsbdExitCode
    set nsbdExitCode 0

    ensure-tables-loaded
    ensure-options-loaded
    nrdInit

    global cfgContents nrdContents
    catch {unset cfgContents}
    catch {unset nrdContents}
    global cmdKeylist procNsbType ignoreSecurity unsignedNsbfiles noNsbChanges
    set cmdKeylist ""
    set procNsbType ""
    set ignoreSecurity 0
    set unsignedNsbfiles 0
    set noNsbChanges 0
    global guiStarted messagesWindow scratchTop scratchFiles
    set guiStarted 0
    set messagesWindow ""
    catch {unset scratchTop}
    set scratchFiles ""
    global saveUnchangedNsbfiles
    set saveUnchangedNsbfiles 0

    package require Tclmd5
    package require Tclsha1

    # set up initial defaults for configuration variables
    #  they will be copied to cfgContents if they're not set there
    #  after all config files are read in
    set defcfgContents(nsbdpath) "~/.nsbd"
    set defcfgContents(configFiles) [list "config.ncf"]
    set defcfgContents(registryFiles) [list "registry.nrd"]
    set defcfgContents(createMask) 22
    global envCfgKeys env cfgKeytable
    foreach key $envCfgKeys {
	set upkey [string toupper $key]
	set val ""
	if {[info exists env($upkey)]} {
	    set val $env($upkey)
	} elseif {[info exists env($key)]} {
	    set val $env($key)
	}
	if {$val != ""} {
	    if {$cfgKeytable($key)} {
		set val [split $val ","]
	    }
	    set defcfgContents($key) $val
	}
    }
    # Process command line keyword settings and info-only options
    eval procargs 1 $args

    global cmdKeytable
    if {[info exists cmdKeytable(nsbdpath)] && ($cmdKeytable(nsbdpath) == "")} {
	# usually setting a command line keyword to "" is ignored, explicitly
	#  allow it for nsbdpath
	set cfgContents(nsbdpath) ""
    }

    foreach key {nsbdpath configFiles createMask} {
	if {[info exists cfgContents($key)]} {
	    set $key $cfgContents($key)
	} else {
	    set $key $defcfgContents($key)
	}
    }
    global cfgFileName
    set cfgFileName [file join $nsbdpath [lindex $configFiles 0]]
    if {$nsbdpath == ""} {
	# nsbdpath overridden to be nothing, not needed for anything
	set defcfgContents(registryFiles) ""
    } elseif {[file exists $cfgFileName]} {
	catch {unset cfgContents(configFiles)}
	procfile $cfgFileName "cfg"
    } elseif {![stdinisatty]} {
	warnmsg "Could not find config file $cfgFileName, continuing without it"
    } else {
	umask $createMask
	initializeCfgFile $cfgFileName
	procfile $cfgFileName "cfg"
    }

    # 
    # process any additional config files
    #
    set numConfigFiles [llength $configFiles]
    set configFileNum 0
    while {1} {
	if {[info exists cfgContents(nsbdpath)]} {
	    # may be a new value if previous value was from default
	    set nsbdpath $cfgContents(nsbdpath)
	}
	if {[info exists cfgContents(configFiles)]} {
	    # use configFiles set in all configuration files
	    foreach configFile $cfgContents(configFiles) {
		incr numConfigFiles [luniqueAppend configFiles $configFile]
	    }
	    unset cfgContents(configFiles)
	}

	if {[incr configFileNum] >= $numConfigFiles} {
	    break
	}

	procfile [file join $nsbdpath [lindex $configFiles $configFileNum]] cfg
    }
    set cfgContents(configFiles) $configFiles

    # now copy in any defaults that weren't yet set
    global cfgKeys
    addKeys $cfgKeys defcfgContents cfgContents cfg

    umask [set cfgContents(createMask) "0$cfgContents(createMask)"]

    #
    # Process nrd files
    #
    set lastRegistryFile ""
    if {![info exists cfgContents(registryFiles)]} {
	set cfgContents(registryFiles) ""
    }
    foreach registryFile $cfgContents(registryFiles) {
	if {$lastRegistryFile != ""} {
	    # all but the last one in the list is read-only, process right away
	    procfile [file join $nsbdpath $lastRegistryFile] nrd
	}
	set lastRegistryFile $registryFile
    }

    global nrdFileName
    set nrdFileName [file join $nsbdpath $lastRegistryFile]
    if {([llength $cfgContents(registryFiles)] == 1) && \
				    ![file exists $nrdFileName]} {
	if {![stdinisatty]} {
	    warnmsg "Could not find registry file $nrdFileName, continuing without it"
	} else {
	    puts ""
	    puts "$nrdFileName did not exist, creating it."
	    puts ""
	    withOpen fd $nrdFileName "w" {
		nsbdGenTemplate $fd nrd non_existent_variable
	    }
	    if {$args == ""} {
		return
	    }
	}
    }

    set hackfile [file join $nsbdpath "hacknsbd.tcl"]
    if {[file exists $hackfile]} {
	debugmsg "Sourcing $hackfile, you're on your own."
	# can't use "source" because it is overridden by mktclapp
	withOpen fd $hackfile "r" {
	    eval [read $fd]
	}
    }

    # Process all the command line arguments
    eval procargs 0 $args
}

#
# Initialize ~/.nsbd interactively
# The main reason this is a separate procedure is to keep nsbdDoit
#   procedure from being too long
#
proc initializeCfgFile {cfgFileName} {
    puts "$cfgFileName did not exist, will create it with template comments."
    puts ""
    puts {When entering pathnames, $ environment variable substitutions}
    puts {   are not supported but ~ substitutions are supported.}
    puts "To operate securely, NSBD requires PGP or GPG.  If you have"
    puts "  PGP 5, use the path of the pgpv program."
    set defaultPgp [whereExecutable pgpv]
    if {$defaultPgp == ""} {
	set defaultPgp [whereExecutable pgp]
    }
    if {$defaultPgp == ""} {
	set defaultPgp [whereExecutable gpg]
    }
    if {$defaultPgp == ""} {
	puts -nonewline "Please enter path of PGP or GPG if you have it: "
    } else {
	puts -nonewline "Please enter path of PGP or GPG \[$defaultPgp\]: "
    }
    flush stdout
    set ans [gets stdin]
    if {$ans == ""} {
	set ans $defaultPgp
    }
    if {$ans != ""} {
	set cfgContents(pgp) $ans
	puts "If you want to change the PGP or GPG path, edit $cfgFileName"
    } else {
	puts "When you get PGP or GPG, put it in the 'pgp' keyword in $cfgFileName"
    }
    puts ""
    puts {To pull files most efficiently, NSBD can use rsync.  However,}
    puts {  because not everyone has rsync, rsync is not preferred over}
    puts {  http unless it is specified in the configuration file.  Unlike}
    puts {  pgp, it is not a security issue if a PATH search is done}
    puts {  instead of a direct path.  Also, you can tell rsync to do}
    puts {  gzip compression with the "-z" option.}
    set defaultRsync ""
    if {[whereExecutable rsync] != ""} {
	set defaultRsync "rsync -z"
    }
    if {$defaultRsync == ""} {
	puts -nonewline "Enter desired rsync command if any: "
    } else {
	puts -nonewline "Please enter desired rsync command \[$defaultRsync\]: "
    }
    flush stdout
    set ans [gets stdin]
    if {$ans == ""} {
	set ans $defaultRsync
    }
    if {$ans != ""} {
	set cfgContents(rsync) $ans
	puts "If you want to change the rsync option, edit $cfgFileName"
    } else {
	puts "If you get rsync, put it in the 'rsync' keyword in $cfgFileName"
    }
    if {![file isdirectory [file dirname $cfgFileName]]} {
	notrace {file mkdir [file dirname $cfgFileName]}
    }
    withOpen fd $cfgFileName "w" {
	nsbdGenTemplate $fd cfg cfgContents
    }

    set mailcap "~/.mailcap"
    if {[file exists $mailcap]} {
	withOpen fd $mailcap "r" {
	    while {[gets $fd line] >= 0} {
		if {[regexp {^application/x-nsbd;} $line]} {
		    set mailcap ""
		    break
		}
	    }
	}
    }
    if {$mailcap != ""} {
	global argv0
	set nsbd [file join [pwd] $argv0]
	if {![file executable $nsbd] || ![file isfile $nsbd]} {
	    set nsbd [whereExecutable nsbd]
	}
	puts ""
	if {$nsbd != ""} {
	    puts "If you want to be able to register for an NSBD-based package by clicking on"
	    puts "   a link in your web browser, NSBD requires an entry in your $mailcap file."
	    puts -nonewline \
		 {Do you want this entry automatically added? [yes] }
	    flush stdout
	    set ans [gets stdin]
	    if {[regexp {[Nn]} $ans]} {
		puts "To add it manually, add a line like this to $mailcap:"
		puts "  application/x-nsbd; $nsbd -register %s"
	    } else {
		puts "Adding a line to $mailcap for launching NSBD registrations from web browser."
		withOpen fd $mailcap "a" {
		    puts $fd ""
		    puts $fd "# NSBD generated mailcap entry at [currentTime]"
		    puts $fd "application/x-nsbd; $nsbd -register %s"
		}
	    }
	} else {
	    puts "Couldn't figure complete path to nsbd, so won't add $mailcap entry."
	    puts "Manually add a line like"
	    puts "  application/x-nsbd; /path/to/nsbd -register %s"
	}
    }
    puts ""
    puts "Thank you for using NSBD.  If you have installed NSBD yourself,"
    puts "  please register for updates from http://www.bell-labs.com/nsbd"
    puts "If you release a package on the internet using NSBD, please"
    puts "  announce it by email to on the NSBD mailing list"
}

#
# Process arguments to nsbd.  The first argument is a boolean set to
#   non-zero if only command line keyword settings and info-only options
#   are to be processed.
# Takes variable number of arguments.
#
proc procargs {preprocOnly args} {
    if {$args == ""} {
	if {$preprocOnly} {
	    return
	}
	usage "no parameters supplied"
    }
    global optionTable infoOnlyOptions
    set optionargc 0
    set invokeOption 0
    foreach arg $args {
	if {$optionargc == 1} {
	    $optionfunc $arg
	    set optionargc 0
	    set invokeOption 0
	} elseif {$optionargc >= 4} {
	    # don't process command line keyword settings
	    lappend optionargs $arg
	} elseif {[set equalidx [string first "=" $arg]] > 0} {
	    proccmdkey [string range $arg 0 [expr $equalidx - 1]] \
		    [string range $arg [expr $equalidx + 1] end] $preprocOnly
	} elseif {$optionargc == 3} {
	    # batch the non-command line keyword settings
	    lappend optionargs $arg
	} elseif {$optionargc == 2} {
	    # all non-command line keyword settings invoke the optionfunc
	    $optionfunc $arg
	    set invokeOption 0
	} elseif {([string index $arg 0] == "-") && ($arg != "-")} {
	    if {[info exists optionTable($arg)]} {
		if {$preprocOnly && ([lsearch -exact $infoOnlyOptions $arg] < 0)} {
		    set optionfunc "nullfunc"
		} else {
		    set optionfunc "option$arg"
		}
		set optionargc $optionTable($arg)
		if {$optionargc == 0} {
		    $optionfunc
		} else {
		    set invokeOption 1
		    set optionargs ""
		}
	    } else {
		usage "unrecognized option $arg"
	    }
	} else {
	    if {!$preprocOnly} {procfile $arg "npd"}
	}
    }
    if {$invokeOption} {
	if {$optionargc == 3} {
	    $optionfunc $optionargs
	} else {
	    $optionfunc [join $optionargs " "]
	}
    }
}

proc nullfunc {args} {
}


#
# procfile accepts a file or a url and knows when urls are valid.
#   A "-" means standard input, of which at most $CONTENT_LENGTH bytes
#   will be read if the CGI-standard environment variable is set.
# The second parameter is the fileType of the type of file that is expected.
# The third parameter varies depending on the expectedType
# If the fourth parameter is present it is the name of an already-existing
#    scratch file to process
#
proc procfile {filename expectedType {typeArg ""} {scratchName ""}} {
    global procNsbType
    if {$scratchName != ""} {
	# the file has already been read into a scratch location
    } elseif {$filename == "-"} {
	set scratchName [scratchAddName "std"]
	set filename "standard input"
	set fd [notrace {open $scratchName "w"}]
	alwaysEvalFor $filename {close $fd} {
	    # copy to a scratch file
	    fconfigure stdin -translation binary
	    fconfigure $fd -translation binary
	    global env
	    if {$procNsbType == "batchUpdate"} {
		copybatchto $fd
	    } elseif {[info exists env(CONTENT_LENGTH)] &&
					($env(CONTENT_LENGTH) != "")} {
		set bytes [fcopy "stdin" $fd -size $env(CONTENT_LENGTH)]
		if {$bytes != $env(CONTENT_LENGTH)} {
		    nsbderror "\$CONTENT_LENGTH indicated $env(CONTENT_LENGTH) bytes but $bytes bytes were read"
		}
	    } else {
		fcopy "stdin" $fd
	    }
	}
    } elseif {$expectedType == "nsb"} {
	# allow a url as a source file; copy it to a local file
	if {$procNsbType == "poll"} {
	    set package $typeArg
	    set ans [urlFile $filename [nrdLookup $package lastServerPollTime]]
	    set scratchName [lindex $ans 0]
	    set serverTime [lindex $ans 1]
	    if {$serverTime != ""} {
		nrdUpdate $package set lastServerPollTime $serverTime
	    } else {
		# was a url, but there's no server time so it must
		#  have not been modified since the lastServerPollTime
		scratchClean $scratchName
		return
	    }
	} else {
	    set code [catch {set ans [urlFile $filename]} message]
	    if {$code > 0} {
		global errorInfo errorCode
		if {([verboseLevel] < 4) && [regexp {.*Not Found} $message]} {
		    # just not found, could be normal so don't show an
		    #  error unless verbosity at least "progress"
		    return
		}
		# else escalate the error
		error $message $errorInfo $errorCode
	    }
	    set scratchName [lindex $ans 0]
	}
    } else {
	set scratchName $filename
    }
    if {[file isdirectory $scratchName]} {
	nsbderror "error: $scratchName is a directory, expecting a file"
    }
    if {$expectedType == "nsb"} {
	# make sure there aren't any lines too long before processing
	# I wish standard gets would support checking for long lines
	#  so wouldn't have to make an extra pass through the file!
	checkLongLines $scratchName $filename
    }
    set fd [notrace {open $scratchName "r"}]
    alwaysEvalFor $filename {close $fd} {
	foreach {fileType lineno hassig} [nsbdFileType $fd $expectedType] {}
	global fileKeywords
	set firstKey $fileKeywords($fileType)
	if {$fileType == "nup"} {
	    nsbderror "$firstKey files not supported for reading"
	}
	if {($fileType) == "nsb" || ($fileType == "npd")} {
	    progressmsg "Processing $filename"
	} else {
	    debugmsg "Processing $filename"
	}
	if {$fileType == "nsb"} {
	    procnsbfile $fd $lineno $filename $typeArg $hassig $scratchName
	} else {
	    if ($hassig) {
		nsbderror "PGP signature only expected on '.nsb' type files"
	    }
	    proc${fileType}file $fd $lineno $filename $typeArg
	}
    }
}

#
# Process a '.npd' NSBD Package Description file
#
proc procnpdfile {fd lineno filename {typeArg ""}} {
    global npdContents nsbContents
    catch {unset npdContents}

    # parse the '.npd' file
    nsbdParseContents $fd npd $lineno $filename npdContents

    # merge in applicable configuration and command line keywords
    global cfgnpdKeys cfgContents
    addKeys $cfgnpdKeys cfgContents npdContents npd
    applyCmdkeys npdContents npd

    if {![info exists npdContents(package)] || ($npdContents(package) == "")} {
	# set default package name
	set npdContents(package) [file root [file tail $filename]]
    }

    global askReason
    if {[info exists askReason]} {
	global env
	set editor vi
	if {[info exists env(EDITOR)]} {
	    set editor $env(EDITOR)
	}
	puts "If you hit return $editor will be brought up."
	puts -nonewline "Reason for update? "
	flush stdout
	set reason [string trim [gets stdin]]
	set doedit 1
	if {$reason != ""} {
	    puts -nonewline {Do you want to edit that reason [n]? }
	    flush stdout
	    set answer [gets stdin]
	    if {![regexp {.*[yY].*} $answer]} {
		set doedit 0
	    }
	}
	if {$doedit} {
	    set tmpfile [scratchAddName "rsn"]
	    withOpen fd $tmpfile "w" {
		puts $fd "# Fill in your reason for this update."
		puts $fd "# Blank lines, indents, and lines beginning with '#' are ignored."
		puts $fd ""
		if {$reason != ""} {
		    puts $fd "$reason"
		}
	    }
	    catch {exec $editor $tmpfile >&@ stderr}
	    set reason ""
	    withOpen fd $tmpfile "r" {
		while {[gets $fd line] >= 0} {
		    set line [string trim $line]
		    if {($line != "") && ([string index $line 0] != "#")} {
			if {$reason != ""} {
			    append reason "\n"
			}
			append reason $line
		    }
		}
	    }
	}
	set npdContents(releaseNote) [split $reason "\n"]
    }

    # construct '.nsb' contents table
    makeNsbContents npdContents nsbContents

    set nsbFilename $nsbContents(package).nsb
    global unsignedNsbfiles
    if {$unsignedNsbfiles} {
	# create an unsigned nsbfile
	nsbdGenFile $nsbFilename nsb nsbContents
	progressmsg "Created an unsigned $nsbFilename"
	if {$unsignedNsbfiles == 2} {
	    set sigfile "$nsbFilename.sig"
	    file delete $sigfile
	    progressmsg "Waiting for $sigfile to appear"
	    while {![file exists $sigfile]} {
		# check again in 5 seconds
		after 5000
	    }
	    # wait 2 more seconds to make sure file is completed
	    after 2000
	    set scratchNsbName [scratchAddName "nsb"]
	    withOpen fdout $scratchNsbName "w" {
		puts $fdout "-----BEGIN PGP SIGNED MESSAGE-----"
		puts $fdout ""
		withOpen fdin $nsbFilename "r" {
		    fcopy $fdin $fdout
		}
		puts $fdout ""
		withOpen fdin $sigfile "r" {
		    while {[set l [gets $fdin line]] >= 0} {
			if {[string range $line [expr {$l - 12}] end] ==
						    "MESSAGE-----"} {
			    set line "[string range $line 0 [expr {$l - 13}]]"
			    set line "${line}SIGNATURE-----"
			}
			puts $fdout $line
		    }
		}
	    }
	    file delete $nsbFilename $sigfile
	    file rename $scratchNsbName $nsbFilename
	    removeFromScratchFiles $scratchNsbName
	    progressmsg "Successfully created $nsbFilename"
	}
    } else {
	# first create an unsigned '.nsb' file, then sign it
	set scratchNsbName [scratchAddName "nsb"]
	nsbdGenFile $scratchNsbName nsb nsbContents

	pgpSignFile $scratchNsbName $nsbFilename

	scratchClean "nsb"
    }
}

#
# Process a '.nrd' NSBD Registry Database file
#
proc procnrdfile {fd lineno filename {contentsName ""}} {
    if {$contentsName == ""} {
	# if no name given, write onto the global nrdContents array
	upvar #0 nrdContents contents
    } else {
	# the contents array name comes from 2 levels up, above procfile
	upvar 2 $contentsName contents
    }

    nsbdParseContents $fd nrd $lineno $filename tmpContents

    global nrdPackagesCache
    foreach key {contents(packages) tmpContents(packages) nrdPackagesCache} {
	if {![info exists $key]} {
	    set $key ""
	}
    }

    # merge the packages list and keep them sorted and unique
    set contents(packages) [lsortUnique \
	    [concat $contents(packages) $tmpContents(packages)]]
    # keep also a sorted unique list of all known packages
    set nrdPackagesCache [lsortUnique \
	    [concat $nrdPackagesCache $contents(packages)]]

    # add the new data to the old
    global nrdKeys
    addKeys $nrdKeys tmpContents contents nrd
}

#
# Process a configuration file
#
proc proccfgfile {fd lineno filename {typeArg ""}} {
    global cfgContents
    nsbdParseContents $fd cfg $lineno $filename cfgContents
}

#
# Copy standard input up through the batch update delimiter to fd, leaving
#    the rest on standard input to avoid having to read all the updates
#    to the temporary file.
# This is run with translation binary so lines may end with carriage return.
# This uses gets before doing checkLongLines, so it does open up a small
#    denial-of-service hole if someone were to deliberately send it an
#    absurdly long line, but that's such a small worry, especially since
#    -batchUpdate is probably only used when the maintainers are relatively
#    trusted.
#
proc copybatchto {fd} {
    global env
    set delim "-----BEGIN BATCH UPDATE-----"
    set line ""
    while {[set n [gets stdin line]] >= 0} {
	if {$n > 1024} {
	    nsbderror "too-long line found while searching for $delim"
	}
	if {[info exists env(CONTENT_LENGTH)] && ($env(CONTENT_LENGTH) != "")} {
	    incr env(CONTENT_LENGTH) [expr {-1 - $n}]
	}
	if {($line == $delim) || ($line == "$delim\r")} {
	    return
	}
	puts $fd $line
	if {[info exists env(CONTENT_LENGTH)] && ($env(CONTENT_LENGTH) != "")
			    && ($env(CONTENT_LENGTH) <= 0)} {
	    break
	}
    }
    nsbderror "did not find $delim in batch input"
}

#
# Check for too-long lines in a file.  If stopat is set, stop
#   checking at a line that contains that value.
#
proc checkLongLines {infile forfile} {
    set fd [notrace {open $infile "r"}]
    alwaysEvalFor $forfile {close $fd} {
	while {[set str [read $fd 1024]] != ""} {
	    if {[string first "\n" $str] < 0} {
		nsbderror "contains a too-long line"
	    }
	}
    }
}

#
# Process a command line keyword setting.  Apply it to the config contents
#   immediately and save it on the cmdKeylist for later application in
#   other places.
# Value may be a list.
#
proc proccmdkey {key value {preprocOnly 0}} {
    global cfgContents cmdKeylist cmdKeytable cfgCmdExceptions
    if {!$preprocOnly} {
	set foundone 0
	foreach fileType {cfg npd nsb} {
	    upvar #0 ${fileType}Keytable keytable
	    if {[info exists keytable($key)]} {
		set foundone 1
		break
	    }
	}
	if {!$foundone} {
	    warnmsg "warning: unknown command line keyword '$key' ignored"
	}
    }
    if {[lsearch -exact $cfgCmdExceptions $key] < 0} {
	applyCmdkey $key $value cfgContents cfg
    }
    if {$preprocOnly} {
	# Only do this during the preproc phase so they're not duplicated
	lappend cmdKeylist $key $value
	set cmdKeytable($key) $value
    }
}

#
# Apply a single command line keyword setting into the contentsname table
#   of type fileType.  A command line setting overrides existing keywords.
#
proc applyCmdkey {key value contentsname fileType} {
    upvar $contentsname contents
    upvar #0 ${fileType}Keytable keytable
    if {[info exists keytable($key)]} {
	if {([lsearch -exact "executableTypes installTop" $key] >= 0) &&
		[info exists contents($key)] &&
		    ![info exists contents(precmd_$key)]} {
	    # save the original
	    set contents(precmd_$key) $contents($key)
	}
	if {$value == ""} {
	    if {[info exists contents($key)]} {
		unset contents($key)
	    }
	} else {
	    if {$keytable($key)} {
		# list is expected
		set contents($key) [split $value ","]
	    } else {
		# value is not expected to be a list
		set contents($key) $value
	    }
	}
    }
}

#
# Apply all comand line keywords onto contentsname table of type fileType.
#
proc applyCmdkeys {contentsname fileType} {
    upvar $contentsname contents
    global cmdKeylist
    foreach {key value} $cmdKeylist {
	applyCmdkey $key $value contents $fileType
    }
}

#
# Retrieve a single command line keyword setting
#
proc getCmdkey {keyname {fileType nsb}} {
    global cmdKeytable
    if {![info exists cmdKeytable($keyname)]} {
	return ""
    }
    # use applyCmdkey into temporary array to expand lists
    applyCmdkey $keyname $cmdKeytable($keyname) tmpcontents $fileType
    if {[info exists tmpcontents($keyname)]} {
	return $tmpcontents($keyname)
    }
    return ""
}

#
# Apply the keys in the fromTable onto the toTable.  Keys that already
#  exist are overridden.
#
proc applyKeys {keys fromTablename toTablename keyfileType} {
    upvar $fromTablename fromTable
    upvar $toTablename toTable
    walkKeys $keys fromTable $keyfileType \
	"applyKeysWalkproc toTable [info level]"
}

proc applyKeysWalkproc {toTablename toTablelevel walkType key value} {
    switch $walkType {
	nonListItem {
	    upvar #$toTablelevel $toTablename toTable
	    set toTable($key) $value
	}
	listTable {
	    upvar #$toTablelevel $toTablename toTable
	    # value is fromTablename
	    upvar $value fromTable
	    set toTable($key) $fromTable($key)
	}
    }
}

#
# Add the keys in the fromTable into the toTable.  Keys that already
#  exist are ignored.
#
proc addKeys {keys fromTablename toTablename keyfileType} {
    upvar $fromTablename fromTable
    upvar $toTablename toTable
    walkKeys $keys fromTable $keyfileType \
	"addKeysWalkproc toTable [info level]"
}

proc addKeysWalkproc {toTablename toTablelevel walkType key value} {
    switch $walkType {
	nonListItem {
	    upvar #$toTablelevel $toTablename toTable
	    if {![info exists toTable($key)]} {
		set toTable($key) $value
	    }
	}
	listTable {
	    upvar #$toTablelevel $toTablename toTable
	    if {![info exists toTable($key)]} {
		# value is fromTablename
		upvar $value fromTable
		set toTable($key) $fromTable($key)
	    }
	}
    }
}

#
# Start up the GUI
#
proc startGui {} {
    global guiStarted
    if {$guiStarted} {
	return
    }
    notrace {startTk}
    set guiStarted 1
    # disable dialog wrapping by putting in a large value for wrapLength
    option add *Dialog.msg.wrapLength 100i
    # set tabs and backtabs in text widgets to switch focus, just like entry
    #  widgets
    bind Text <Tab> [bind Entry <Tab>]
    bind Text <Shift-Tab> [bind Entry <Shift-Tab>]

    if {[info commands "real_tk_dialog"] != "real_tk_dialog"} {
	#
	# prevent dialogs from grabbing the keyboard focus
	#
	# do the catch here to get it loaded
	catch {tk_dialog}
	rename tk_dialog real_tk_dialog
	proc tk_dialog {args} {
	    global dialog_dont_grab
	    set dialog_dont_grab 1
	    set ans [eval real_tk_dialog $args]
	    unset dialog_dont_grab
	    return $ans
	}
	rename grab real_grab
	proc grab {args} {
	    global dialog_dont_grab
	    if {![info exists dialog_dont_grab] || ([llength args] != 1)} {
		eval real_grab $args
	    }
	}
    }


    wm withdraw .
    makeMessagesWindow
}

#
# stop the GUI.  I haven't figured out any way to restart it once stopped,
#   so it's generally not a good idea to do this.
#
proc stopGui {} {
    global guiStarted
    set guiStarted 0
    deleteMessagesWindow
    destroy .
}

#
# Return the name of a scratch file based on a short name
#
proc scratchName {name} {
    global scratchTop
    if {![info exists scratchTop]} {
	global cfgContents
	if {[info exists cfgContents(tmp)]} {
	    set tmp $cfgContents(tmp)
	} else {
	    set tmp "/tmp"
	}
	set scratchTop [file join $tmp "n[pid]"]
    }
    return $scratchTop$name
}

#
# Add a name to the scratchFiles list
#

proc addToScratchFiles {scratchFile} {
    global scratchFiles
    debugmsg "Adding scratch file $scratchFile"
    luniqueAppend scratchFiles $scratchFile
}

#
# Remove a name from the scratchFiles list
#

proc removeFromScratchFiles {scratchFile} {
    global scratchFiles
    set idx [lsearch -exact $scratchFiles $scratchFile]
    if {$idx >= 0} {
	debugmsg "Removing $scratchFile from the list of scratch files"
	set scratchFiles [lreplace $scratchFiles $idx $idx]
    }
}

#
# Add the scratch name to the list of scratch files and return the full pathname
#
proc scratchAddName {name} {
    set scratchFile [scratchName $name]
    addToScratchFiles $scratchFile
    return $scratchFile
}

#
# Remove scratch file(s)
#
proc scratchClean {{names ""}} {
    global scratchFiles
    if {$names == ""} {
	# scratchFiles may not exist yet if this is being
	#  called as a result of a very early error
	if {[info exists scratchFiles]} {
	    set names $scratchFiles
	}
    }
    foreach name $names {
	set idx [lsearch -exact $scratchFiles $name]
	if {$idx < 0} {
	    set scratchFile [scratchName $name]
	    set idx [lsearch -exact $scratchFiles $scratchFile]
	} else {
	    set scratchFile $name
	}
	debugmsg "Cleaning scratch file $scratchFile"
	# this needs to be -force so it can recursively remove
	#  the temporaryTop directory
	if {[catch {file delete -force $scratchFile} string] > 0} {
	    warnmsg "error deleting $scratchFile: $string"
	}
	if {$idx >= 0} {
	    set scratchFiles [lreplace $scratchFiles $idx $idx]
	}
    }
}

