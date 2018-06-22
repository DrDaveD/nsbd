#!/bin/sh
#
# simple CGI script for maintainers of packages that sets the MIME
#  "Content-Type" for '.nsb' files so they can be recognized by web browsers.
# Install a symbolic link to this file in the same directory as the '.nsb'
#  file or a directory above the '.nsb' file but still accessible as a
#  URL, and make sure that it is recognized as a script by your http
#  server (my http server is configured to treat all files that end
#  in ".cgi" as scripts, so that's the name I choose for the symbolic
#  link).  Then, make a hyperlink on your web page to be the URL for
#  the script followed by a question mark (?) followed by a path to
#  the '.nsb' file relative to the directory that the script is
#  installed in.  For example,
#      http://www.bell-labs.com/nsbd/linknsb.cgi?nsbd.nsb
#  Alternatively, set the extension '.nsb' in your http server's
#  mime.types file to have the content-type of "application/x-nsbd"
#  and then hyperlink to the '.nsb' file directly.
#
# Written by Dave Dykstra <dwd@bell-labs.com> 11 Dec 1996
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

error()
{
ME=`basename $0`
cat <<!END!
Content-Type: text/html

<HTML>
<HEAD>
<TITLE>
Error from $ME
</TITLE>
<BODY>
<H1>
Error from $ME:
</H1>
<H3>
<P>
$*
</H3>
!END!

exit

}

F="${QUERY_STRING:-}"
if [ "$F" = "" ]
then
    error "expected a ? parameter of a '.nsb' Not-So-Bad Distribution file"
fi

case "/$F/" in
    //*) error "parameter must be a relative pathname";;
    */../*) error 'parameter may not contain ".." components';;
esac

if [ ! -r "$F" ]
then
    error "cannot read $F"
fi

echo "Content-Type: application/x-nsbd"
echo
cat "$F"
