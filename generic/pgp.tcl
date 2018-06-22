#
# NSBD interface functions to PGP and GnuPG.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 13 Dec 1996
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
# Get the name of the pgp program and its variant, and set up any environment
#  variables it needs.  Pgptype is "verify", "sign", or "key" to select the
#  separate programs in pgp5.
# Return list of two things:
#   1. The name of the pgp program.
#   2. The variant ("pgp", "pgp5", or "gpg").
#
proc getpgp {pgptype {pgppath_override ""}} {
    global cfgContents env
    if {![info exists cfgContents(pgp)]} {
	global cfgFileName
	nsbderror  \
"\"pgp\" configuration keyword not set.  A complete path to PGP is recommended
  in the \"pgp:\" keyword in $cfgFileName for security. 
  If you do not have PGP, you can use the \"-ignoreSecurity\" command line
  option when installing packages, but then you throw out security.  To create
  an unsigned '.nsb' file you can use the \"-unsigned\" command line option
  or you can use \"-wait4signature\" to wait for a manually created PGP
  signature."
    }
    set pgp $cfgContents(pgp)

    set variant "pgp"
    regexp {^[^ 	]*} $pgp pgpcom
    if {[info exists cfgContents(pgpVariant)]} {
	set variant $cfgContents(pgpVariant)
    } else {
	if {[regexp {pgpv$} $pgpcom]} {
	    set variant "pgp5"
	} elseif {[regexp {gpg$} $pgpcom]} {
	    set variant "gpg"
	}
    }

    if {$variant == "pgp5"} {
	if {![regexp {v$} $pgpcom]} {
	    nsbderror "first word of pgp keyword for pgp5 variant must end with 'v'"
	}
	set replaceVwith "v"
	if {$pgptype == "sign"} {
	    set replaceVwith "s"
	} elseif {$pgptype == "key"} {
	    set replaceVwith "k"
	}
	set before [string range $pgp 0 [expr {[string length $pgpcom] - 2}]]
	set after [string range $pgp [string length $pgpcom] end]
	set pgp "$before$replaceVwith$after"
    }

    set pgppath ""
    if {$pgppath_override != ""} {
	set pgppath $pgppath_override
    } elseif {[info exists cfgContents(pgppath)]} {
	set pgppath [expandTildes $cfgContents(pgppath)]
    }
    if {($variant == "pgp") || ($variant == "pgp5")} {
	if {$pgppath != ""} {
	    set pgp "PGPPATH=$pgppath;export PGPPATH;$pgp"
	}
	#verbose=0 doesn't seem necessary on pgp5 but doesn't hurt
	set pgp "$pgp +verbose=0"
    } elseif {$variant == "gpg"} {
	if {$pgppath != ""} {
	    set pgp "GNUPGHOME=$pgppath;export GNUPGHOME;$pgp"
	}
	set pgp "TZ=GMT;export TZ;$pgp --no-greeting --no-secmem-warning"
    } else {
	nsbderror "unrecognized pgpVariant $pgpVariant; see nsbd -help pgpVariant"
    }
    return [list $pgp $variant]
}

#
# Get the name of the term program
#
proc getterm {} {
    global cfgContents
    if {[info exists cfgContents(termCommand)]} {
	return $cfgContents(termCommand)
    }
    return "xterm"
}

#
# Apply pgp signature to $inFile, leaving signed file in $outFile
#
proc pgpSignFile {inFile outFile} {
    set ans [getpgp sign]
    set pgp [lindex $ans 0]
    set variant [lindex $ans 1]
    # don't use progressmsg here, want to prompt the user
    puts "Invoking $variant to create signature for $outFile"
    set inFile [expandTildes $inFile]
    set outFile [expandTildes $outFile]
    set pgpopts ""
    if {$variant == "gpg"} {
	set pgpopts "--detach-sign --yes"
	# there's a problem with gpg that prevents it from making a
	#   detachable signature if it is initially created non-detached
	set finalFile $outFile
	set outFile [scratchAddName "sig"]
    } elseif {$variant == "pgp5"} {
	set pgpopts "+force"
    } else {
	set pgpopts "-s"
    }
    if {$variant != "pgp"} {
	# don't need to filter gpg or pgp5 output
	# use popen "w" followed by close just because it's the simplest
	#   way to invoke a subprocess; gpg and pgp5 don't need stdin
	set fd [notrace {popen "$pgp $pgpopts -at -o $outFile $inFile" "w"}]
	set retcode [catch {close $fd} msg]
	if {$retcode != 0} {
	    if {$msg == "child process exited abnormally"} {
		set msg ""
	    } else {
		# have seen a shell startup script message come here so print it
		set msg ":\n  $msg"
	    }
	    nsbderror "error creating $variant signature$msg"
	}
	if {$variant == "pgp5"} {
	    global cfgContents
	    set perm [format "0%o" [expr "0666" & ~$cfgContents(createMask)]]
	    changeMode $outFile $perm
	} elseif {$variant == "gpg"} {
	    # attach the detached signature
	    if {$inFile == $finalFile} {
		# need to make yet another temporary file
		set copyFile [scratchAddName "cpy"]
		file copy $inFile $copyFile
		set inFile $copyFile
	    }
	    withOpen fdout $finalFile "w" {
		withOpen fdin $inFile "r" {
		    puts $fdout "-----BEGIN PGP SIGNED MESSAGE-----"
		    puts $fdout ""
		    fcopy $fdin $fdout
		    puts $fdout ""
		}
		withOpen fdin $outFile "r" {
		    fcopy $fdin $fdout
		}
	    }
	    if {[info exists copyFile]} {
		scratchClean $copyFile
	    }
	    scratchClean $outFile
	    set outFile $finalFile
	}
	progressmsg "Successfully signed $outFile"
	return
    }
    set fd [notrace {popen "$pgp $pgpopts -at $inFile" "r"}]
    alwaysEvalFor $outFile {catch {close $fd}} {
	set sigfile ""
	set getpass 0
	# eat up first line if it is blank
	gets $fd line
	debugmsg "$variant sent: $line"
	if {$line != ""} {
	    puts $line
	}
	while {[gets $fd line] >= 0} {
	    debugmsg "$variant sent: $line"
	    # The prompts may be different depending on the version of PGP.
	    # Tested with pgp 2.6.2 and viacrypt pgp 4.0 business edition,
	    #
	    set firstfour [wrange $line 0 3]
	    if {$firstfour == "Key for user ID"} {
		# pgp 2.6.2
		puts $line
		set getpass 1
		continue
	    }
	    if {$getpass && ($line != "")} {
		# this line should have been blank; in case not really blank
		puts $line
	    }
	    set firsttwo [wrange $line 0 1]
	    if {$getpass || ($firsttwo == "with userid:")} {
		# first case pgp 2.6.2, second case pgp 4.0
		puts -nonewline "Enter Passphrase: "
		flush stdout
		set getpass 0
		continue
	    }
	    set firstone [windex $line 0]
	    if {$firstone == "\aError:"} {
		# pgp 4.0
		puts $line
		set getpass 1
		continue
	    }
	    set firstthree [wrange $line 0 2]
	    if {($firstthree == "Enter pass phrase:") ||
		    ($firsttwo == "Enter Passphrase:") ||
			($firsttwo == "Enter Passphrase:\a")} {
		# first form pgp 2.6.2, second and third forms pgp 4.0
		# eat up the prompt that PGP put out, but put out a
		#  newline because echoing was turned off for password
		puts ""
		continue
	    }
	    if {($firstthree == "To sign file:") ||
		    ($firstthree == "Error code =")} {
		# pgp 4.0
		continue
	    }
	    if {$firstthree == "Clear signature file:"} {
		set sigfile [windex $line 3]
		addToScratchFiles $sigfile
		progressmsg "Successfully signed $outFile"
		continue
	    }
	    if {$line != ""} {
		puts $line
	    }
	}
    }
    if {$sigfile == ""} {
	nsbderror "error creating pgp signature"
    }
    # Need to make a copy of the file simply because pgp always changes
    #  the umask to be 077, and want default umask.  Otherwise, could
    #  use "-o" option on pgp (which still appends ".asc", so would
    #  still need to at least rename the file and would need to be careful
    #  to put it in the same filesystem as the destination or rename will
    #  do a copy too.)
    withOpen fdout $outFile "w" {
	withOpen fdin $sigfile "r" {
	    fcopy $fdin $fdout
	}
    }
    scratchClean $sigfile
}

#
# Check the pgp signature in $sigFile.  sigFile may be a temporary name, so
#   use forFile as the name for error messages instead; if forFile is empty
#   no name will be added to the error messages.
# Return value is in 4 parts:
#   1. The pgp variant.
#   2. A boolean (1 or 0) that indicates if the signature was good or not.
#   3. A list of the ids of the signature, if they could be determined
#      (good or bad).  If the public key could not be found, the id returned
#      is "*UNKNOWN*".
#   4. Any warning or error messages, possibly including newlines.

proc pgpCheckFile {signedFile {forFile ""}} {
    # Note: there are two reasons to separate the plaintext from the signature
    #  into two temporary files.  One is to allow multiple signatures in the
    #  future, and the other is that with a combined file pgp will attempt to
    #  create a plaintext file without the signature.  The only way around that
    #  is to apply the option "-o $signedFile" so the default filename will be
    #  the same as $inFile and it won't overwrite an existing file and it will
    #  return an error code.
    progressmsg "Checking PGP signature on [expr {$forFile == "" ? $signedFile : $forFile}]"
    set ans [getpgp verify]
    set pgp [lindex $ans 0]
    set variant [lindex $ans 1]
    set signedFile [expandTildes $signedFile]
    # pgp5 requires extension on a detached signature !@$%
    set sigFile [scratchAddName "pln.sig"]
    set plainFile [scratchAddName "pln"]
    set foundsig 0
    withOpen fd $signedFile "r" {
	withOpen fdplain $plainFile "w" {
	    gets $fd line
	    while {[string range $line 0 4] == "-----"} {
		# skip beginning header(s) that start with ----
		while {![eof $fd] && ([string trim $line] != "")} {
		    # skip up through first blank line
		    gets $fd line
		}
		# ignore beginning blank line
		gets $fd line
	    }
	    set blanks ""
	    while {![eof $fd]} {
		if {[string trim $line] == ""} {
		    append blanks "$line\n"
		    gets $fd line
		    continue
		}
		if {[string range $line 0 4] == "-----"} {
		    # now into ending signature blocks
		    break
		}
		if {$blanks != ""} {
		    # save blank lines in the middle of the file
		    puts -nonewline $fdplain $blanks
		    set blanks ""
		}
		puts $fdplain $line
		gets $fd line
	    }
	    # skip ending blank lines
	    while {![eof $fd]} {
		if {[string range $line 0 23] == "-----BEGIN PGP SIGNATURE"} {
		    withOpen fdsig $sigFile "w" {
			while {![eof $fd]} {
			    puts $fdsig $line
			    gets $fd line
			    if {[string range $line 0 21] == "-----END PGP SIGNATURE"} {
				set foundsig 1
				puts $fdsig $line
				break
			    }
			}
		    }
		}
		gets $fd line
	    }
	}
    }
    if {!$foundsig} {
	scratchClean "pln"
	scratchClean "pln.sig"
	return {0 "" "" "Did not find complete signature block"}
    }

    if {$variant == "gpg"} {
	set pgpopts "--batch --verify"
    } else {
	set pgpopts "+batchmode"
    }
    set fd [notrace {popen "$pgp $pgpopts $sigFile $plainFile" "r"}]
    set good 0
    set ids ""
    set warning ""
    alwaysEvalFor "" {catch {close $fd}} {
	while {[gets $fd line] >= 0} {
	    debugmsg "$variant sent: $line"
	    # The prompts may be different depending on the version of PGP.
	    # Tested with pgp 2.6.2, viacrypt pgp 4.0, business edition
	    #   and gpg 0.9.7
	    if {$variant == "gpg"} {
		if {[windex $line 0] != "gpg:"} {
		    continue
		}
		set line [wrange $line 1 end]
	    }
	    switch -regexp -- $line {
		"^Good signature from user " {
		    # pgp 2.6.2
		    set good 1
		    regexp {^Good signature from user "([^"]*)"} $line x user
		    lappend ids $user
		}
		"^Good signature from user:  " {
		    # pgp 4.0
		    set good 1
		    regexp {^Good signature from user:  ([^"]*)} $line x user
		    lappend ids $user
		}
		"^Good signature from " {
		    # gpg 0.4.0
		    set good 1
		    regexp {^Good signature from "([^"]*)"} $line x user
		    lappend ids $user
		}
		"^Good signature made.*by key:" {
		    # pgp 5.0
		    set good 1
		    while {[gets $fd line] > 0} {
			if {[regexp {Key ID ([0-9A-F]*)} $line x keyid]} {
			    lappend ids "0x$keyid"
			} elseif {[regexp {"([^"]*)"} $line x user]} {
			    lappend ids $user
			}
		    }
		}
		"^Bad signature from user " {
		    # pgp 2.6.2
		    set good 0
		    regexp {^Bad signature from user "([^"]*)"} $line x user
		    lappend ids $user
		}
		"Bad signature from user:  " {
		    # pgp 4.0
		    set good 0
		    regexp {Bad signature from user:  ([^"]*)} $line x user
		    lappend ids $user
		}
		"^BAD signature from " {
		    # gpg 0.9.7
		    set good 0
		    regexp {^BAD signature from "([^"]*)"} $line x user
		    lappend ids $user
		}
		"^BAD signature made.*by key:" {
		    # pgp 5.0
		    set good 0
		    while {[gets $fd line] > 0} {
			if {[regexp {Key ID ([0-9A-F]*)} $line x keyid]} {
			    lappend ids "0x$keyid"
			} elseif {[regexp {"([^"]*)"} $line x user]} {
			    lappend ids $user
			}
		    }
		}
		"^Signature made.*key ID" {
		    # gpg 0.9.7
		    regexp {key ID ([0-9A-F]*)} $line x keyid
		    lappend ids "0x$keyid"
		}
		"Signature made " {
		    # ignore this date message from pgp 2.6 or pgp 4.0
		}
		"using insecure memory!" {
		    # ignore this message from gpg
		} 
		"unsafe permissions on file" {
		    # ignore this message from gpg
		}
		"^This signature applies to another message" {
		    # ignore this message from pgp 5.0
		}
		"^Opening file" {
		    # ignore this message from pgp 5.0
		}
		default {
		    if {$line == "\a"} {
		        # seen in pgp 2.6.2 and pgp 4.0
			gets $fd msg
		    } elseif {[string index $line 0] == "\a"} {
		        # seen in pgp 2.6.2 and pgp 4.0
			set msg [string range $line 1 end]
		    } else {
			set msg $line
		    }
		    set wordzero [windex $msg 0]
		    if {$wordzero == ""} {
			# skip blank lines
			continue
		    }
		    if {$wordzero == "ERROR:"} {
		        # seen in pgp 2.6.2 and pgp 4.0
			lappend warning [wrange $msg 1 end]
		    } else {
			if {$wordzero == "WARNING:"} {
		            # seen in all variants
			    set msg [wrange $msg 1 end]
			} elseif {$variant == "pgp"} {
			    # non-WARNINGS can be ignored in pgp 2.6.2 and 4.0
			    continue
			} elseif {$variant == "pgp5"} {
			    # non-WARNINGs are one-liners in pgp5
			    lappend warning $msg
			    continue
			}
			if {$wordzero == "Warning:"} {
		            # seen in gpg 0.4.0
			    set msg [wrange $msg 1 end]
			} 
			if {![regexp "Output file.*already exists" $msg] &&
			    ![regexp "Key matching expected.*not found" $msg] &&
			    ![regexp "Problem with clear result" $msg]} {
			    # skip expected messages in pgp 2.6.2 and pgp 4.0
			    lappend warning $msg
			}
			if {$wordzero == "Warning:"} {
		            # I've only seen one-line Warnings in gpg 0.4.0
			    continue
			} 
			while {([gets $fd msg] > 0) &&
			  (($variant != "pgp") || ![regexp {^[A-Z]} $msg])} {
			    # pgp 2.6.2 follows warning by blank lines, but the
			    #  pgp 4.0 warnings that I've seen are followed by
			    #  lines that begin with upper case letters, and
			    #  they're lines that I don't care about
			    # gpg 0.4.0 WARNINGs I've seen are only at the
			    #   end of the output and have whitespace on
			    #   subsequent lines
			    # pgp 5.0 WARNINGs I've seen are followed by
			    #   blank lines
			    if {$variant == "gpg"} {
				if {[windex $msg 0] == "gpg:"} {
				    set msg "  [wrange $msg 1 end]"
				}
			    } elseif {$variant == "pgp5"} {
				lappend warning "  $msg"
			    } else {
				lappend warning $msg
			    }
			}
		    }
		}
	    }
	}
    }
    set warning [join $warning "\n"]
    if {!$good} {
	if {[wrange $warning 0 4] == "Can't find the right public"} {
	    # pgp 2.6.2 and 4.0
	    set ids "*UNKNOWN*"
	} elseif {[wrange $warning 0 2] == "Can't check signature:"} {
	    # gpg 0.9.7
	    set ids "*UNKNOWN*"
	} elseif {[wrange $warning 0 3] == "Signature by unknown keyid:"} {
	    # pgp 5.0
	    set ids "*UNKNOWN*"
	}
    }
    set newids ""
    foreach id $ids {
	if {[string range $id 0 11] == {[uncertain] }} {
	    # this can happen in gpg 1.0.7 and later
	    set id [string range $id 12 end]
	}
	lappend newids $id
    }
    set ids $newids
    scratchClean "pln.sig"
    scratchClean "pln"
    return [list $variant $good $ids $warning]
}

#
# Return 1 if id is known to PGP, otherwise return 0
#

proc pgpIDKnown {id} {
    set ans [getpgp key]
    set pgp [lindex $ans 0]
    set variant [lindex $ans 1]
    if {$variant == "gpg"} {
	set pgpopts "--batch -kv"
    } elseif {$variant == "pgp5"} {
	set pgpopts "+batchmode +force -l"
    } else {
	set pgpopts "+batchmode -kv"
    }
    set fd [notrace {popen "$pgp $pgpopts \"$id\"" "r"}]
    alwaysEvalFor "" {set retcode [catch {close $fd}]} {
	while {[gets $fd line] >= 0} {
	    debugmsg "$variant sent: $line"
	    if {($variant == "pgp") || ($variant == "pgp5")} {
		if {[regexp {^([^ ]*) matching key(s)? found} $line x n x] ||
		    [regexp {^matching key(s)? found:  ([^ ]*)} $line x x n]} {
			# the former is what pgp 2.6.2 and pgp 5.0 says and
			#    the latter is what pgp 4.0 says
			return [expr {$n > 0}]
		}
	    }
	}
    }
    if {$variant == "gpg"} {
	# use the error code for gpg 0.9.7
	return [expr {$retcode == 0}]
    }
    return 0
}

#
# Pop up a new window to interactively run pgp to add a key
#
proc pgpAddKey {id keyfile} {
    set ans [getpgp key]
    set pgp [lindex $ans 0]
    set variant [lindex $ans 1]
    if {$variant == "gpg"} {
	set scratch1 [scratchAddName "a.gpg"]
	scratchAddName "a.gpg~"
	set scratch2 [scratchAddName "b.gpg"]
	eval exec "[getterm] -T {GPG for NSBD} -e [getshell] -c {
	    # need to just select an individual key out of the keyfile
	    echo Calling gpg to extract key
	    echo \"    \" \"$id\"
	    > $scratch1
	    $pgp --keyring $scratch1 --import $keyfile
	    # export only handles one matching key, find all with --list-keys
	    IDS=\"`$pgp --keyring $scratch1 --list-keys '$id' | \
			sed -n '/$id/{s,\[^/\].*/,,;s, .*,,p;}'`\"
	    $pgp --keyring $scratch1 --export -o $scratch2 \$IDS
	    echo Calling gpg to add the key
	    $pgp --keyring $scratch2 --fingerprint
	    $pgp --import $scratch2
	    echo
	    echo 'You will now be given the opportunity to sign the key(s).'
	    echo 'To sign, type \"sign\" followed by \"save\", or type \"help\" for more options.'
	    for ID in \$IDS; do 
		echo
		echo 'Editting key id' \$ID
		$pgp --edit-key \$ID
	    done
	    echo Hit return to continue with nsbd...
	    read DUMMY
	}"
	scratchClean "a.gpg"
	scratchClean "a.gpg~"
	scratchClean "b.gpg"
    } elseif {$variant == "pgp"} {
	set scratch1 [scratchAddName "a.pgp"]
	# all tested pgp's create an empty a.bak file
	scratchAddName "a.bak"
	# pgp 4.0 can't handle a scratch2 name with a ".pgp" extension,
	#   but pgp 2.6.2 can
	set scratch2 [scratchAddName "key2"]
	# pgp 2.6.2 adds a ".pgp" extension to key2, but pgp 4.0 does not
	scratchAddName "key2.pgp"
	eval exec "[getterm] -T {PGP for NSBD} -e [getshell] -c {
	    echo Calling pgp to extract key
	    echo \"    \" \"$id\"
	    # need to temporarily add to $scratch1 because pgp cannot
	    #  extract an id from an ascii-armored keyfile
	    $pgp +batchmode -ka $keyfile $scratch1 >/dev/null
	    # first $scratch2 is for pgp 2.6.2 and -o $scratch2 is for pgp 4.0
	    $pgp +batchmode -kx \"$id\" $scratch2 $scratch1 -o $scratch2
	    echo Calling pgp to add the key
	    # pgp 4.0 doesn't handle putting -kvc keyring at the end of command
	    #  line although pgp 2.6.2 does, so using +pubring instead
	    $pgp +pubring=$scratch2 -kvc \"$id\"
	    $pgp -ka $scratch2
	    echo Hit return to continue...
	    read DUMMY
	}"
	scratchClean "a.pgp"
	scratchClean "a.bak"
	scratchClean "key2"
	scratchClean "key2.pgp"
    } elseif {$variant == "pgp5"} {
	# Despite documentation, cannot set the pubring on the pgpk
	#   command line in pgp 5.0!!  It works in pgpe.  Grrrrrr...
	set scratchdir [scratchAddName "pgpd"]
	file delete -force $scratchdir
	file mkdir $scratchdir
	#create empty pgp.cfg and randseed.bin
	close [open "$scratchdir/pgp.cfg" "w"]
	close [open "$scratchdir/randseed.bin" "w"]
	set tmppgp [lindex [getpgp key $scratchdir] 0]

	eval exec "[getterm] -T {PGP5 for NSBD} -e [getshell] -c {
	    echo Calling pgp5 to extract key
	    echo \"    \" \"$id\"
	    (
	    # run tmppgp in subshell so PGPPATH will be unset when finished
	    $tmppgp +batchmode -a $keyfile >/dev/null
	    $tmppgp +batchmode -x \"$id\" -o $scratchdir/extract.key
	    echo
	    echo Calling pgp to add the key
	    $tmppgp -ll \"$id\"
	    )
	    $pgp -a $scratchdir/extract.key
	    echo
	    echo \"Calling pgp to certify the key (in case it isn't in your ring of trust)\"
	    $pgp -s \"$id\"
	    echo
	    echo Calling pgp to edit introducing trust for the key
	    $pgp -e \"$id\"
	    echo Hit return to continue...
	    read DUMMY
	}"
	scratchClean "pgpd"
    } else {
	nsbderror "pgpAddKey for variant $variant not implemented yet"
    }
}
