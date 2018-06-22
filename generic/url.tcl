# NSBD interface functions to tcl's standard http library and to rsync. 
#  Also handles reading multiple files in a single network connection,
#  calculating checksums on files retrieved, and doing binary file relocation.
#
# File created by Dave Dykstra <dwd@bell-labs.com>, 09 Jan 1997
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
# proxyfilter for Tcl's http builtin functions
#
proc nsbdHttpProxyFilter {host} {
    # Warning: includes hacks to allow support for ftp through an http
    #  proxy; has knowledge of the implementation of the http library.
    #  Specifically, it knows that the variable name in http_get that
    #  holds the url is "url", and it knows that http_get directly calls
    #  this filter with no intermediate routines such that the variables
    #  from urlGet are exactly 2 levels up
    upvar 2 reallyFtp reallyFtp
    upvar 2 proxyHostAndPort proxyHostAndPort
    if {[info exists reallyFtp]} {
	upvar url url
	regsub "^http:" $url "ftp:" url
    }
    upvar state state
    if {$proxyHostAndPort != ""} {
	# While we're at it, also set proxyAuthorization here because it's
	# easier to do here than in a wrapper where -headers may already
	# be set to something
	global proxyAuthorization
	set with ""
	if {[info exists proxyAuthorization]} {
	    lappend state(-headers) Proxy-Authorization $proxyAuthorization
	    set with " with proxy authorization"
	}

	debugmsg "  using proxy $proxyHostAndPort$with"
    }

    # Also set Pragma: no-cache here always, to request that proxies always
    #   give the latest version.  When HTTP/1.1 is implemented in proxies,
    #   and it can be determined that all proxies in the chain are compliant
    #   with HTTP/1.1 (which can only be known after the first operation to a
    #   particular server is completed), it will be better to instead use
    #   Cache-Control: max-age=0.  That requests that proxies only confirm
    #   that an object is up-to-date (presumably with If-Modified-Since), not
    #   necessarily reload it.  On the other hand, apparently many current
    #   proxies (at least Netscape and CERN) already do that for no-cache.
    lappend state(-headers) Pragma no-cache

    return $proxyHostAndPort
}

http_config -proxyfilter nsbdHttpProxyFilter

#
# Interface to http_get that also allows ftp through an http proxy
#
proc urlGet {args} {
    set url [HMmap_reply [lindex $args 0]]
    if {[lsearch -glob $args "-query*"] >= 0} {
	progressmsg "POSTing to $url"
    } else {
	progressmsg "Fetching $url"
    }
    global cfgContents
    if {[regexp -nocase "^http://(\[^/:\]+)" $url x host]} {
	if {![info exists cfgContents(http_proxy)]} {
	    set proxyHostAndPort ""
	} elseif {[info exists cfgContents(no_proxy)]} {
	    # look through list of domains for which to not use the proxy
	    foreach domain $cfgContents(no_proxy) {
		if {[regexp -nocase "\.$domain\$" $host] || \
				[regexp -nocase "^$domain\$" $host]} {
		    set proxyHostAndPort ""
		    break
		}
	    }
	}
	if {![info exists proxyHostAndPort]} {
	    if {![regexp -nocase "^http://(\[^:/\]*)(:(\[^/\]*))?(/)?\$" \
			$cfgContents(http_proxy) x phost y pport]} {
		nsbderror {http_proxy must be in form http://proxyhost[:portno][/] (default portno is 8080)}
	    }
	    if {$pport == ""} {
		set pport 8080
	    }
	    set proxyHostAndPort "$phost $pport"
	}
    } elseif {[regsub "^ftp://" $url "http://" url]} {
	set reallyFtp 1
	if {![info exists cfgContents(ftp_proxy)]} {
	    nsbderror "ftp only supported through a proxy, and ftp_proxy not set"
	}
	if {![regexp -nocase "^http://(\[^:/\]*)(:(\[^/\]*))?(/)?\$" \
			$cfgContents(ftp_proxy) x phost y pport]} {
	    nsbderror {ftp_proxy must be in form http://proxyhost[:portno][/] (default portno is 8080)}
	}
	if {$pport == ""} {
	    set pport 8080
	}
	set proxyHostAndPort "$phost $pport"
    } else {
	nsbderror "url must begin with http:// or ftp://: $url"
    }
    # Set proxyAuthorization global if config var present and using proxy
    global proxyAuthorization
    if {($proxyHostAndPort != "") && 
		[info exists cfgContents(proxyAuthorization)] &&
		    ![info exists proxyAuthorization]} {
	set proxyAuthorization \
		"Basic [base64Encode $cfgContents(proxyAuthorization)]"
    }
    if {$proxyHostAndPort != ""} {
	# set up for possible error opening socket
	set for "proxy [join $proxyHostAndPort ":"]"
    } else {
	set for ""
        regexp -nocase "^http://(\[^/:\]+(:\[0-9\]+)?)" $url x for
    }
    if {[info exists cfgContents(httpUserAgent)]} {
	http_config -useragent $cfgContents(httpUserAgent)
    }
    return [alwaysEvalFor "$for" {} {
		# the -command option makes it run in the "background",
		#   that is, it avoids immediately calling http_wait
		notrace {eval http_get $url -command urlGetDone \
				[lrange $args 1 end]}
	    }]
}

proc urlGetDone {token} {
    # do nothing - just forces http_get into background
}

#
# Check results of an http operation for errors.   If there were any,
#  raise a TCL error condition
#
proc httpCheck {token url} {
    upvar #0 $token state
    if {![info exists state(http)]} {
	# I don't know if there are any other reasons this could be,
	#  but this is the only one I've seen, and there's no other
	#  way to tell a timeout I don't think
	nsbderror "timed out getting $url header"
    }
    set httpCode [lindex $state(http) 1]
    if {$httpCode >= 400} {
	nsbderror "error getting $url: $state(http)"
    }
    if {($state(totalsize) > 0) && ($state(currentsize) < $state(totalsize))} {
	nsbderror "$url length incorrect: expected $state(totalsize), got $state(currentsize)"
    }
}

#
# Display url get or post progress messages
#
proc urlProgress {token total current} {
    upvar #0 $token state
    if {$total == 0} {
	# total is unknown
	return
    }
    set level [verboseLevel]
    if {$level < 5} {
	return
    }
    if {$level > 5} {
	set delay 0
    } else {
	set delay 3
    }
    # note: the percent is later assumed to be rounded down
    set percent [expr {int($current * 100.0 / $total)}]
    if {[info exists state(percentdone)] &&
					($state(percentdone) == $percent)} { 
	return
    }

    if {$percent == 100} {
	catch {unset state(progresstime)}
	if {[info exists state(percentdone)]} {
	    if {$state(percentdone) == 100} {
		# already printed done message
		return
	    }
	} elseif {($delay > 0)} {
	    # never printed anything
	    return
	}
    } else {
	if {$delay > 0} {
	    if {![info exists state(progresstime)]} {
		set state(progresstime) [clock seconds]
		return
	    }
	    set now [clock seconds]
	    if {$now - $state(progresstime) < $delay} {
		return
	    }
	    set state(progresstime) $now
	}
    }
    set state(percentdone) $percent
    set msg "  $percent% of $total bytes done"
    global messagesWindow
    if {$messagesWindow != ""} {
	if {$percent == 100} {
	    set msg "$msg\n"
	}
	$messagesWindow delete "insert linestart" insert
	$messagesWindow insert end "$msg"
	$messagesWindow see end
	update idletasks
    } else {
	if {$percent == 100} {
	    puts -nonewline stderr "$msg\n"
	} else {
	    puts -nonewline stderr "$msg\r"
	}
	flush stderr
    }
}

#
# Copy a url to a local file.  Let the end-of-line translation be
#   automatically selected (text file is assumed).
# If the "if-modified-since" is set (to a canonical time), will ask the
#   server to only retrieve the file if it has been modified since that
#   time; if it had not, will return an empty string, otherwise will return
#   the server time in PGP format if available, or the current local time.
# If not successful, an error will be raised.
#

proc urlCopy {url localfile {ifModifiedSince ""} {extraArgs ""}} {
    if {[regexp -nocase {^rsync://} $url]} {
	if {[regexp -- "-query" $extraArgs]} {
	    nsbderror "cannot POST to rsync"
	}
	urlRsyncCopy $url $localfile
	return
    }
    if {![regexp -nocase {^ftp://|^http://} $url]} {
	# do this early check to be able to include rsync in error message
	nsbderror "url must begin with http://, ftp://, or rsync://: $url"
    }
    if {$ifModifiedSince != ""} {
	lappend extraArgs -headers [list "If-Modified-Since" $ifModifiedSince]
    }
    if {$localfile != "-"} {
	set fd [notrace {open $localfile "w"}]
	alwaysEvalFor "" {close $fd} {
	    # using -channel causes binary mode to be used only when
	    #   the Content-type is not text
	    #  set token [eval "urlGet $url -channel $fd" $extraArgs]
	    set token [eval "urlGet $url \
			-handler \"urlCopyHandler $fd\"" $extraArgs]
	    alwaysEvalFor $localfile {} {
		notrace {http_wait $token}
	    }
	}
    } else {
	set fd stdout
	set savetranslation [fconfigure $fd -translation]
	# using -channel causes binary mode to be used only when
	#   the Content-type is not text
	#  fconfigure $fd -translation binary
	#  set token [eval "urlGet $url -channel $fd" $extraArgs]
	set token [eval "urlGet $url \
			-handler \"urlCopyHandler $fd\"" $extraArgs]
	notrace {http_wait $token}
	fconfigure $fd -translation $savetranslation
    }
    httpCheck $token $url
    upvar #0 $token state
    if {$ifModifiedSince != ""} {
	set httpCode [lindex $state(http) 1]
	if {$httpCode == 304} {
	    progressmsg "  wasn't modified since $ifModifiedSince, skipping"
	    http_reset $token
	    return ""
	}
    }
    array set meta $state(meta)
    http_reset $token
    if {[info exists meta(Date)]} {
	return [canonicalizeTime $meta(Date)]
    } else {
	# use our own time if can't find it from the server
	return [currentTime]
    }
}

#
# This is called whenever data is available on the url.  Return the
#  number of bytes read.  This is a vanilla handler except that it puts
#  the file descriptors into binary mode; it wasn't obvious how to do
#  it outside of a handler.
#
proc urlCopyHandler {fd socket token} {
    upvar #0 $token state
    if {![info exists state(afterFirstBlock)]} {
	# always want binary, no matter what the Content-type is
	fconfigure $socket -translation binary
	fconfigure $fd -translation binary
	set state(afterFirstBlock) 1
    }

    # I would use fcopy but it has got the annoying habit of blocking
    #   until all data is read unless you use the -command option
    set block [read $socket $state(-blocksize)]
    set n [string length $block]
    if {$n > 0} {
	puts -nonewline $fd $block
    }
    return $n
}

#
# Copy urlOrFile to a local scratch file and return the name of the
#  scratch file.
# Also return the server time of the URL file as a second return value
#  if known.
# 

proc urlFile {urlOrFile {ifModifiedSince ""}} {
    set scratchName [scratchAddName "ucp"]
    if {[regexp {://} $urlOrFile]} {
	if {[regexp {file://[^/]*(.+)} $urlOrFile x topPath]} {
	    # accept "file://"-type URLs since local files are allowed
	    if {![file exists $topPath]} {
		nsbderror "$topPath does not exist"
	    }
	    notrace {file copy -force $topPath $scratchName}
	    return [list $scratchName]
	}
	return [list $scratchName \
	    [urlCopy $urlOrFile $scratchName $ifModifiedSince "-progress urlProgress"]]
    }
    notrace {file copy -force $urlOrFile $scratchName}
    return [list $scratchName]
}

#
# Copy a url to a local file while calculating the message digest checksum.  
#   mdType is message digest type.  When finished, compare the message digest
#   with the expectedMdData.
# If not successful, an error will be raised.
#

proc urlMdCopy {url fromPath mdType expectedMdData localfile reloc {mode ""}} {
    set url "$url/$fromPath"
    if {$mode == ""} {
	set mode "0666"
    }
    set fd [withParentDir {openbreloc $localfile $reloc "w" $mode} $localfile]
    set mdDescriptor [$mdType -init]
    alwaysEvalFor "" {closebreloc $fd} {
	set token [urlGet $url -handler "urlMdCopyHandler $fd" \
						-progress urlProgress]
	upvar #0 $token state
	set state(mdType) $mdType
	set state(mdDescriptor) $mdDescriptor
	alwaysEvalFor $localfile {} {
	    notrace {http_wait $token}
	}
    }
    httpCheck $token $url
    http_reset $token
    compareMdDataFor $fromPath $expectedMdData [$mdType -final $mdDescriptor] 
}

#
# This is called whenever data is available on the url.  Return the
#  number of bytes read.
#
proc urlMdCopyHandler {fd socket token} {
    upvar #0 $token state
    if {![info exists state(afterFirstBlock)]} {
	# always want binary, no matter what the Content-type is
	fconfigure $socket -translation binary
	fconfigure $fd -translation binary
	set state(afterFirstBlock) 1
    }
    return [$state(mdType) -update $state(mdDescriptor) -chan $socket \
			-copychan $fd -maxbytes $state(-blocksize)]
}

#
# Fetch multiple files in one http connection, or from an open file
#  descriptor if that is provided instead of a url, and check the
#  message digest checksums
# Assumes talking to a CGI script on the other side (unless fd is set) that
#  accepts file names in a POST to its standard input, and then for each file
#  puts out the filename in a Content-Name: header and the length in
#  Content-Length: followed by a blank line followed by the data for the file.
# mdType is message digest type
# pathsInfo is a list of info about each path.  Info is a list of
#   1. fromPath - path to retrieve
#   2. toTop - top directory of path to store into
#   3. finalPath - path that file is eventually stored into (this function
#	mainly ignores this and stores the file in $toTop/$fromPath)
#   4. mode - mode of file to store
#   5. mdData - the expected message digest data for the file (length and
#		message digest checksum)
#   6. installTop - (optional, and not used in this function) the top
#		directory of where the file will be ultimately installed
#   7. reloc - optional "from=to" translation to apply to relocating the
#		data in the file after calculating the checksum
# fd is file descriptor of an open file to use instead of a URL
# maxBytes, if set, is the maximum number of bytes to read from fd
#
proc urlMultiMdCopy {url mdType pathsInfo {fd ""} {maxBytes ""}} {
    set numpaths [llength $pathsInfo]
    if {$numpaths == 0} {
	return ""
    }
    set paths ""
    set sep ""
    if {$fd == ""} {
	foreach pathInfo $pathsInfo { 
	    append paths $sep[lindex $pathInfo 0]
	    set sep "\n"
	}
	set token [urlGet $url -query $paths -handler urlMultiMdCopyHandler]
    } else {
	set token $fd
    }
    upvar #0 ${token}_multi multi
    set multi(mdType) $mdType
    alwaysEvalFor "" {
			if {[info exists multi(fd)]} {close $multi(fd)}
			set multistate $multi(state)
			set pathnum $multi(pathnum)
			set remaining $multi(remaining)
			catch {unset multi}
		     } {
	set multi(state) init
	set multi(pathnum) 0
	set multi(remaining) 0
	set multi(pathsInfo) $pathsInfo
	if {$fd == ""} {
	    notrace {http_wait $token}
	} elseif {$maxBytes != ""} {
	    while {$maxBytes > 0} {
		if {[eof $fd]} {
		    nsbderror "multi-fetch had premature end of file, $maxBytes bytes missing"
		}
		incr maxBytes -[urlMultiMdCopyHandler $fd $token $maxBytes]
	    }
	} else {
	    while {![eof $fd]} {
		urlMultiMdCopyHandler $fd $token
	    }
	}
    }
    if {$fd == ""} {
	httpCheck $token $url
	http_reset $token
    }
    if {$multistate != "want-Keyword"} {
	if {($multistate == "reading-Content") && ($remaining > 0)} {
	    nsbderror "multi-fetch had premature end of file, $remaining bytes remaining in file $pathnum"
	}
	nsbderror "data was not in multiget format (in state $multistate)"
    }
    if {$pathnum != $numpaths} {
	nsbderror "multi-fetched $pathnum files but expected $numpaths"
    }
}

#
# This is called whenever data is available on the url.  Return the
#  number of bytes read.  Read no more than maxBytes if set
#
proc urlMultiMdCopyHandler {socket token {maxBytes ""}} {
    upvar #0 $token state
    upvar #0 ${token}_multi multi
    set mdType $multi(mdType)
    if {$multi(state) == "init"} {
	if {[info exists state(meta)]} {
	    foreach {keyword value} $state(meta) {
		if {[regexp -nocase {^x-multiget-error$} $keyword]} {
		    nsbderror "error from multiget remote:\n    $value"
		}
	    }
	}
	fconfigure $socket -translation binary
	set multi(state) want-Keyword
    }
    if {$multi(state) != "reading-Content"} {
	# note that the line may have a carriage return in it
	# can't let tcl strip that out because it would mess up the byte count
	set bytes [expr {[gets $socket line] + 1}]
	if {($bytes == 0) && [fblocked $socket]} {
	    # the socket is in -blocking off mode, so gets will return -1
	    #   if a complete line is not available
	    return 0
	}
	set line [string trimright $line "\r"]
	set keyword ""
	if {[regexp {^([^:]+):(.+)$} $line x keyword value]} {
	    set value [string trim $value]
	} elseif {$line != ""} {
	    nsbderror "bad multiget header format in state $multi(state), got\n    [string range $line 0 60]"
	}
	if {[regexp -nocase {^x-multiget-error$} $keyword]} {
	    nsbderror "error from multiget remote:\n    $value"
	}
	if {$multi(state) == "want-Keyword"} {
	    if {$line != ""} {
		set multi(state) want-Content-Name
	    }
	}
	if {$multi(state) == "want-Content-Name"} {
	    set pathInfo [lindex $multi(pathsInfo) $multi(pathnum)]
	    if {$pathInfo == ""} {
		set pathInfo [list "" "" "" ""]
	    }
	    foreach {fromPath toTop finalPath mode mdData xx reloc} $pathInfo {}
	    if {$finalPath == ""} {
		# there is no final path so just copy into the top
		# this is for -fetchAll where the file is thrown out
		set toPath $toTop
	    } else {
		set toPath [file join $toTop $fromPath]
	    }
	    if {$line == ""} {
		nsbderror "Content-Name header not found (expected $fromPath)"
	    }
	    if {[regexp -nocase {^content-name$} $keyword]} {
		if {$fromPath != $value} {
		    nsbderror "url multi-fetch retrieved unexpected path $value, expected $fromPath"
		}
		set multi(fromPath) $fromPath
		set multi(toPath) $toPath
		set multi(mdData) $mdData
		set multi(mdDescriptor) [$mdType -init]
		set multi(fd) [withParentDir \
			{openbreloc $toPath $reloc "w" $mode} $toPath]
		set multi(state) want-Content-Length
		incr multi(pathnum)
		# moved to end to workaround bug in plus patch that causes this
		#  event handler to sometimes be nested when "update idletasks"
		#  is called within the progressmsg.  10 October 1997
		transfermsg "Multi-fetching $fromPath"
	    }
	} elseif {$multi(state) == "want-Content-Length"} {
	    if {$line == ""} {
		nsbderror "Content-Length header for $multi(fromPath) not found"
	    }
	    if {[regexp -nocase {^content-length$} $keyword]} {
		if {![regexp {^[0-9]+$} $value]} {
		    nsbderror "Content-Length value \"$value\" is not a number"
		}
		set multi(remaining) $value
		set multi(expected) $value
		set multi(state) "want-blank-line"
	    }
	} elseif {$multi(state) == "want-blank-line"} {
	    if {$line == ""} {
		set multi(state) reading-Content
	    }
	}
	return $bytes
    }

    if {[info exists state(-blocksize)]} {
	set blocksize $state(-blocksize)
    } else {
	# this handler is sometimes called without urlGet/http_get
	set blocksize 8192
    }
    if {$blocksize > $multi(remaining)} {
	set blocksize $multi(remaining)
    }
    if {($maxBytes != "") && ($blocksize > $maxBytes)} {
	set blocksize $maxBytes
    }
    if {$blocksize > 0} {
	set bytes [$mdType -update $multi(mdDescriptor) -chan $socket \
			-copychan $multi(fd) -maxbytes $blocksize]
    } else {
	set bytes 0
    }
    incr multi(remaining) -$bytes
    if {$multi(remaining) == 0} {
	closebreloc $multi(fd)
	unset multi(fd)
	if {$multi(mdData) != ""} {
	    set mdData [$mdType -final $multi(mdDescriptor)]
	    compareMdDataFor $multi(fromPath) $multi(mdData) $mdData
	}
	set multi(state) want-Keyword
    }
    # moved to end to workaround bug in plus patch that causes this
    #  event handler to sometimes be nested when "update idletasks"
    #  is called within the urlProgress.  10 October 1997
    urlProgress $token $multi(expected) \
	[expr {$multi(expected) - $multi(remaining)}]
    return $bytes
}

#
# Compare expected message digest data to received data for $path 
# Raise an error if they don't match
#
proc compareMdDataFor {path expectedMdData mdData} {
    set expectedLength [lindex $expectedMdData 0]
    set expectedMd [lindex $expectedMdData 1]
    set length [lindex $mdData 0]
    set md [lindex $mdData 1]
    if {$length != $expectedLength} {
	nsbderror "wrong length of $path: got $length, expected $expectedLength"
    }
    if {[string compare $md $expectedMd] != 0} {
	nsbderror "wrong message digest for $path: got $md, expected $expectedMd"
    }
}

# From "Uhler's html_library", as posted by Steve Ball on comp.lang.tcl

# do x-www-urlencoded character mapping
# The spec says: "non-alphanumeric characters are replaced by '%HH'"
 
global HMalphanumeric
global HMform_map
set HMalphanumeric      a-zA-Z0-9       ;# definition of alphanumeric character class
# add other characters I don't want translated
set HMalphanumeric	"-${HMalphanumeric}*,./:?_~=&+"
for {set i 1} {$i <= 256} {incr i} {
    set c [format %c $i]
    if {![string match \[$HMalphanumeric\] $c]} {
        set HMform_map($c) %[format %.2x $i]
    }
}
 
# These are handled specially
array set HMform_map {
    " " +   \n %0d%0a
}
 
# 1 leave alphanumerics characters alone
# 2 Convert every other character to an array lookup
# 3 Escape constructs that are "special" to the tcl parser
# 4 "subst" the result, doing all the array substitutions
 
proc HMmap_reply {string} {
    global HMform_map HMalphanumeric
    regsub -all \[^$HMalphanumeric\] $string {$HMform_map(&)} string
    regsub -all \n $string {\\n} string
    regsub -all \t $string {\\t} string
    regsub -all {[][{})\\]\)} $string {\\&} string
    return [subst $string]
}

#
# base64 encoding routines, submitted by Simon King
# Simplifications by Dave Dykstra
# This would be much easier and faster done in C, but speed is not at all
#   critical because this is only done once per session
#

# Turns decimal values to binary 8 bits wide
proc dec2bin8 {decNum} {
    global H2B
    if {![info exists H2B(0)]} {
	array set H2B "0 0000 1 0001 2 0010 3 0011 4 0100 5 0101 6 0110 7 0111"
	array set H2B "8 1000 9 1001 a 1010 b 1011 c 1100 d 1101 e 1110 f 1111"
    }
    set hexNum [format "%02x" $decNum]
    return "$H2B([string index $hexNum 0])$H2B([string index $hexNum 1])"
}

# Turns decimal values to binary 6 bits wide
proc dec2bin6 {decNum} {
    global O2B
    if {![info exists O2B(0)]} {
	array set O2B "0 000 1 001 2 010 3 011 4 100 5 101 6 110 7 111"
    }
    set octNum [format "%02o" $decNum]
    return "$O2B([string index $octNum 0])$O2B([string index $octNum 1])"
}

# Turns a text string into its binary representation
proc makeBitStream inputText {
    # Make an array containing the ASCII character set.
    # The index is the character, and the value is its binary representation
    for {set i 0} {$i <= 255} {incr i} {
	eval "set asciiSet([format "\\%o" $i]) [dec2bin8 $i]"
    }
    for {set i 0} {$i < [string length $inputText]} {incr i} {
	append bitStream "$asciiSet([string index $inputText $i])"
    }
    return $bitStream
}

# Finally, a routine that turns a text string into its base64 representation
# For the record, it should turn the string "Aladdin:open sesame"
# into "QWxhZGRpbjpvcGVuIHNlc2FtZQ=="
proc base64Encode inputText {
    # Create base64Set to convert binary bits to ascii base64
    # Some useful values :
    set decA 65
    set deca 97
    set dec0 48
    # Capitals :
    for {set i 0} {$i <= 25} {incr i} {
	eval "set base64Set([dec2bin6 $i]) \
			[format "\\%o" [expr $i + $decA]]"
    }
    # Lower case :
    for {set i 0} {$i <= 25} {incr i} {
	eval "set base64Set([dec2bin6 [expr $i + 26]]) \
			[format "\\%o" [expr $i + $deca]]"
    }
    # Numbers :
    for {set i 0} {$i <= 9} {incr i} {
	eval "set base64Set([dec2bin6 [expr $i + 52]]) \
			[format "\\%o" [expr $i + $dec0]]"
    }
    # And finally,
    set base64Set(111110) "+"
    set base64Set(111111) "/"

    set bitStream [makeBitStream $inputText]
    set padding ""
    for {set i 0} {$i < [string length $bitStream]} {set i [expr $i + 6]} {
	set block [string range $bitStream $i [expr $i + 5]]
	if {[string length $block] == 2} {
	    append block 0000
	    set padding "=="
	} elseif {[string length $block] == 4} {
	    append block 00
	    set padding "="
	}
	append encodedText $base64Set($block)
    }
    append encodedText $padding
    return $encodedText
}

#
# Copy from an rsync server
#

proc urlRsyncCopy {url localfile {extraArgs ""}} {
    #
    # NOTE: because we are invoking the shell, be sure to quote anything
    #   that is directly passed in from the maintainer to prevent them from
    #   sticking in any sneaky shell syntax
    # Also explicitly check for special characters that may defeat the quotes.
    #

    if {[regexp {['"\\]} $url]} {
	nsbderror "rsync url may not contain quotes or backslashes"
    }

    progressmsg "Fetching from $url"

    global cfgContents env
    if {[info exists cfgContents(rsync)]} {
	set rsync $cfgContents(rsync)
    } else {
	set rsync "rsync -z"
    }

    set tostdout 0
    if {$localfile == "-"} {
	set tostdout 1
	set localfile [scratchAddName "sto"]
    }

    set com "$rsync --timeout 120 -L $extraArgs '$url' [expandTildes $localfile]"

    set isVerbose [expr {[regexp -- {-[^ ]*v} $extraArgs] || \
			 [regexp -- {-[^ ]*v} $rsync]}]
    set msgs ""
    set fd [notrace {popen $com "r"}]
    # need to use non-blocking mode and an event handler in order to prevent
    #  the appearance of hanging when using a TK GUI
    fconfigure $fd -blocking off
    global rsyncOutputAvailable
    fileevent $fd readable {set rsyncOutputAvailable 1}
    alwaysEvalFor "" {set retcode [catch {
					fileevent $fd readable {}
					close $fd
				    } errmsg]} {
	while {1} {
	    set rsyncOutputAvailable 0
	    vwait rsyncOutputAvailable
	    set line [gets $fd]
	    if {[eof $fd]} {
		break
	    }
	    if {[fblocked $fd]} {
		# don't have a full line yet
		continue
	    }
	    if {$isVerbose} {
		# Could use progressmsg but put it at noticemsg in case
		#  someone set the rsync variable to "rsync -v" at a lower
		#  level.  Don't want to use errormsg or warnmsg because those
		#  can pop up requestors.
		noticemsg $line
	    } else {
		set msgs "$msgs\n    $line"
	    }
	}
    }
    if {$retcode != 0} {
	nsbderror "error running rsync$msgs"
    } elseif {$msgs != ""} {
        warnmsg "Warning: unexpected output from rsync:$msgs"
    }

    if {$tostdout} {
	withOpen fd $localfile "r" {
	    fconfigure $fd -translation binary
	    set stdoutConfig [fconfigure stdout -translation]
	    fconfigure stdout -translation binary
	    fcopy $fd stdout
	    fconfigure stdout -translation $stdoutConfig
	}
	scratchClean $localfile
    }
}

#
# Copy "paths" from the rsync "url" to the top level "toTop", optionally
#   comparing with the top level "compareTop".
#

proc urlRsyncMultiCopy {url toTop paths compareTop {copyTimes 0}} {
    set excludeFrom [scratchAddName "exf"]
    debugmsg "creating $excludeFrom:"
    withOpen fd $excludeFrom "w" {
	foreach path $paths {
	    set dpath $path
	    set revdpaths ""
	    while {[set dpath [file dirname $dpath]] != "."} {
		# include each parent directory that hasn't already been
		#   included
		if {[info exists dpaths($dpath)]} {
		    break
		}
		# reverse the order
		set revdpaths [concat [list $dpath] $revdpaths]
	    }
	    foreach dpath $revdpaths {
		debugmsg "  + /$dpath"
		puts $fd "+ /$dpath"
		set dpaths($dpath) ""
	    }
	    # include the path
	    debugmsg "  + /$path"
	    puts $fd "+ /$path"
	}
	# exclude the rest
	debugmsg "  - *"
	puts $fd "- *"
    }

    if {$copyTimes} {
	set extraArgs "-t"
    } else {
	# should I only be doing this if -t isn't in in cfgContents($rsync)?
	set extraArgs "-I"
    }
    set extraArgs "$extraArgs -rL --partial --exclude-from $excludeFrom"
    if {$compareTop != ""} {
	set extraArgs "$extraArgs --compare-dest [expandTildes $compareTop]"
    }
    if {[verboseLevel] >= 5} {
	set extraArgs "$extraArgs -v"
    }
    if {[string index $url [expr [string length $url] - 1]] != "/"} {
	set url "$url/"
    }
    urlRsyncCopy $url $toTop $extraArgs
    scratchClean $excludeFrom
}

#
#
# Copy multiple files from an rsync server and check message digest checksums.
# For a description of the parameters see the comments at urlMultiMdCopy.
#

proc urlRsyncMultiMdCopy {url mdType pathsInfo} {
    global cfgContents
    set createMask $cfgContents(createMask)

    set paths ""
    set prevInstallTop ""
    foreach pathInfo $pathsInfo {
	foreach {fromPath toTop finalPath xx xx installTop xx} $pathInfo {}
	if {($fromPath != $finalPath) && ($finalPath != "")} {
	    # rsync cannot apply substitutions, so attempt to
	    #  hardlink in substituted name from installTop into
	    #  toTop so rsync will have something to compare to
	    set installPath [file join $installTop $finalPath]
	    set toPath [file join $toTop $fromPath]
	    debugmsg "hardlinking $installPath into $toPath"
	    catch {withParentDir {hardLink $installPath $toPath}}
	}
	if {$installTop != $prevInstallTop} {
	    # I don't think this is likely to happen in practice,
	    #   but it is conceivable
	    if {$paths != ""} {
		notrace {file mkdir $toTop}
		urlRsyncMultiCopy $url $toTop $paths $installTop
		set paths ""
	    }
	    set prevInstallTop $installTop
	}
	lappend paths $fromPath
    }

    notrace {file mkdir $toTop}
    urlRsyncMultiCopy $url $toTop $paths $installTop

    #defaultperm is the permissions that all files would have been created with
    set defaultperm [format "0%o" [expr ~$createMask & "0666"]]

    foreach pathInfo $pathsInfo {
	foreach {fromPath toTop finalPath mode expectedMdData xx reloc} $pathInfo {}

	if {$reloc == "="} {
	    set reloc ""
	}
	if {$reloc != ""} {
	    progressmsg "Relocating $reloc in $fromPath"
	}
	set toPath [file join $toTop $fromPath]

	# check message digest checksum and if relocation is necessary do
	#   it on the same pass through the data
	set code [catch {set fd [open $toPath "r"]}]
	if {$code != 0} {
	    nsbderror "rsync did not transfer $fromPath"
	}
	alwaysEvalFor $fromPath {catch {close $fd}} {
	    fconfigure $fd -translation binary
	    if {$reloc == ""} {
		set mdData [$mdType -chan $fd]
	    } else {
		set tmpPath [file join [file dirname $toPath] ".breloctmp"]
		set rfd [openbreloc $tmpPath $reloc "w" $mode]
		# do *not* catch the closebreloc in case there was an
		#   error in the relocation
		alwaysEvalFor "" {closebreloc $rfd} {
		    set mdData [$mdType -chan $fd -copychan $rfd]
		}
		# move the relocated file into place
		file delete $toPath
		file rename $tmpPath $toPath
	    }
	}
	compareMdDataFor $fromPath $expectedMdData $mdData

	if {($mode == "") || ($reloc != "")} {
	    continue
	}
	# maskedperm is the permissions it should have
	set maskedperm [format "0%o" [expr $mode & ~$createMask & "0777"]]
	if {$maskedperm != $defaultperm} {
	    changeMode $toPath $maskedperm
	}
    }
}
