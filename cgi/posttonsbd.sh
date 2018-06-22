#!/bin/sh
#
# CGI script for users of packages that want to allow direct "pushing"
#   of package updates.  This should be installed as three separate CGI
#   scripts to invoke the nsbd options -changedPaths, -batchUpdate, and
#   -preview separately.  The first two are needed because a single http
#   POST operation can only do a single request-result exchange, and
#   the third is for the convenience of the maintainer to see what
#   will be installed before actually doing it. 
# The $NSBD environment variable, if set, points to a path to the nsbd
#   program.  The option selected can either come as $OPTIONNAME or the
#   script name.
# For changedPaths, you may want to set NSBD="path_to_nsbd verbose=0" to avoid
#   displaying any progress messages which will come again with batchUpdate.
#
# NOTE: typically an extra http server program is needed to be run on
#   an unused port to just invoke this CGI script, under the user id
#   that owns the directories that are to be written into, because
#   usually the main http server on a computer is not set up to allow
#   CGI scripts to write to the desired directories.  Also note that
#   in this mode of operation, users typically register packages by
#   hand by manually editting their registry.nrd file and listing the
#   "validPaths" for each package.
#	
# Written by Dave Dykstra <dwd@bell-labs.com> 21 August 1997
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

NSBD=${NSBD:-nsbd}
OPTIONNAME=${OPTIONNAME:-`basename $0`}
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

if [ "$OPTIONNAME" = "preview" ]
then
    PACKAGE=-
else
    PACKAGE="${QUERY_STRING:-}"
    if [ -z "$PACKAGE" ]
    then
	error "expected a ? parameter of package_name"
    fi
fi
if [ -z "${CONTENT_LENGTH:-}" ]
then
    error "No CONTENT_LENGTH environment variable; must be invoked as a CGI from an http POST"
fi

exec 2>&1
echo "Content-Type: application/octet-stream"
echo
$NSBD -$OPTIONNAME "$PACKAGE"
exit 0
