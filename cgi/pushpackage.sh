#!/bin/sh
#
# Program for maintainers of packages to directly "push" updates of
#   their packages to users, even if the maintainer is on the inside of
#   a firewall.  Requires the user to have set up posttonsbd for calls to
#   -changedPaths, -batchUpdate, and -preview.  Expects some environment
#   variables to be set to locate things, so it is typically invoked
#   through a small wrapper script (supplied by the user) which sets
#   those variables and then includes it with ".".  Note that in this mode
#   of operation maintainers can leave out many of the keywords needed in
#   the normal "automated pull" mode, needing little more than the "paths"
#   keyword in their '.npd' files.
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
#

# path to NSBD program
NSBD=${NSBD:?must_be_set}
# directory that the remote CGI scripts are in
POSTURLBASE=${POSTURLBASE:?must_be_set}
# name for the changedPaths CGI script, optional
CHANGEDPATHS=${CHANGEDPATHS:-changedPaths}
# name for the batchUpdate CGI script, optional
BATCHUPDATE=${BATCHUPDATE:-batchUpdate}
# name for the preview CGI script, optional
PREVIEW=${PREVIEW:-preview}

CMD=`basename $0`
USAGE="Usage: $CMD [-prepareOnly|-skipPrepare] [-preview] \\
    [-unsigned|-wait4signature] [-askreason] [nsbd_variable_settings] [package]
  A package.npd file is expected in the current directory.  If package is
	not specified, and exactly one *.npd exists, it will be used.
  A package.nsb file is created in the current directory by the prepare step
	and used by the push step.
  If -prepareOnly is used, only the prepare step is done.
  If -skipPrepare is used, the prepare step is skipped.
  If -preview is used, nothing is pushed and only the changes that would
	be made are printed.
  -unsigned, -wait4signature, and -askreason options and/or nsbd variable
	settings of form 'key=value' are sent directly to nsbd during the
	prepare step."

usage()
{
    if [ $# != 0 ]
    then
	echo "$CMD: $*" >&2
    fi
    echo "$USAGE" >&2
    exit 2
}
abort()
{
    echo "$CMD: $*" >&2
    exit 1
}

PREPARE=yes
PUSH=yes
CHANGED=""
PACKAGE=""
VERBOSE=yes
LOCALTOP=""
NSBDOPTS=""
for ARG
do
    case "$ARG" in
	-prepareOnly) 
	    PREPARE=yes
	    PUSH=""
	    ;;
	-skipPrepare)
	    PREPARE=""
	    PUSH=yes
	    ;;
	-pushOnly)
	    echo "$CMD: note: -pushOnly has been renamed to -skipPrepare, proceeding"
	    PREPARE=""
	    PUSH=yes
	    ;;
	-preview)
	    DOPREVIEW=yes
	    PUSH=yes
	    ;;
	-changedPaths) 
	    abort "the -changedPaths option has been replaced by -preview"
	    ;;
	-unsigned|-wait4signature|-askreason)
	    NSBDOPTS="$NSBDOPTS $ARG"
	    ;;
	-*)
	    usage "unrecognized option $ARG"
	    ;;
	*=*)
	    NSBDOPTS="$NSBDOPTS \"$ARG\""
	    case "$ARG" in
		verbose=[01234]) VERBOSE=no;;
		localTop=*) LOCALTOP="$ARG"
	    esac
	    ;;
	*)
	    if [ ! -z "$PACKAGE" ]
	    then
		usage "only give one package"
	    fi
	    PACKAGE="$ARG"
	    ;;
    esac
done

if [ -z "$PACKAGE" ]
then
    NPDFILES="`echo *.npd`"
    case "$NPDFILES" in
	"*.npd") usage "no *.npd file found";;
	*" "*) usage "more than one *.npd file found";;
    esac
    PACKAGE="`echo $NPDFILES|sed 's/\.npd//'`"
fi

if [ "$PREPARE" = "yes" ]
then
    if [ ! -f $PACKAGE.npd ]
    then
	abort "can't find $PACKAGE.npd file in current directory"
    fi
    set -e
    eval $NSBD "$NSBDOPTS" $PACKAGE.npd
    set +e
fi

if [ "$PUSH" != "yes" ]
then
    exit
fi

if [ ! -f $PACKAGE.nsb ]
then
    abort "can't find $PACKAGE.nsb file in current directory"
fi

if [ "$DOPREVIEW" = yes ]
then
    $NSBD -postUrl $POSTURLBASE/$PREVIEW < $PACKAGE.nsb
    exit $?
fi

TMP=/tmp/nsbdpp$$
trap "rm -f $TMP.*" 0

stopat()
{
    # this has to be sent to sh -c because of bug in ksh93d, at least on IRIX
    #  awk and sed can't do it because they read too much from a pipeline
    # need to set IFS= to keep "read" from stripping leading & trailing blanks
    /bin/sh -c 'IFS=; while read LINE
    do
	if test "$LINE" = '\""$1"\"'
	then
	    exit 0
	fi
	echo "$LINE"
    done
    exit 1'
}
# these functions are for detecting errors in pipelines
pipeerror()
{
    echo $? >$TMP.EC
}
checkpipeerror()
{
    if [ -f $TMP.EC ]
    then
	exit `cat <$TMP.EC`
    fi
}

if [ "$VERBOSE" = yes ]
then
    echo "Determining changed paths"
fi
rm -f $TMP.CP
{
  $NSBD -postUrl $POSTURLBASE/$CHANGEDPATHS?$PACKAGE < $PACKAGE.nsb || pipeerror
} | (
    stopat "-----BEGIN CHANGED PATHS-----"
    stopat "-----END CHANGED PATHS-----" >$TMP.CP
    cat
    )

checkpipeerror

if [ ! -f $TMP.CP ]
then
    abort "could not determine changed paths"
fi


if [ -n "$LOCALTOP" ]
then
    # localTop was set on the command line
    LOCALTOP="`echo $LOCALTOP|sed 's/localTop=//'`"
    if [ -z "$LOCALTOP" ]
    then
	LOCALTOP=.
    fi
else
    # find localTop out of the .npd file if present
    if [ ! -f $PACKAGE.npd ]
    then
	abort "can't find $PACKAGE.npd in current directory; need it to look for localTop"
    fi
    LOCALTOP=`while read KEY VAL
	do
	    if [ "$KEY" = "localTop:" ]
	    then
		if [ -z "$VAL" ]
		then
		    read VAL
		    case "$VAL" in
			*:|"") abort "can't find value for localTop in $PACKAGE.npd"
		    esac
		fi
		echo "$VAL"
		exit
	    fi
	done <$PACKAGE.npd
	echo .`
    fi

genbatchupdate()
{
    (cat $PACKAGE.nsb
    echo "-----BEGIN BATCH UPDATE-----"
    cd $LOCALTOP
    {
	CONTENT_LENGTH="" $NSBD -multigetFiles <$TMP.CP || pipeerror
    } | (# skip up through the first blank line out of multiget
	stopat "" >/dev/null
	cat))
    checkpipeerror
}

if [ "$VERBOSE" = yes ]
then
    echo "Determining length of updates"
fi
BATCHLENGTH="`{
		genbatchupdate || pipeerror
	     } | wc -c`"
if (checkpipeerror)
then
    :
else
    # presumably the same error will occur again
    genbatchupdate | grep -i "^x-multiget-error:"
    checkpipeerror
fi

# get rid of leading blanks
BATCHLENGTH="`echo $BATCHLENGTH`"

{
    genbatchupdate || pipeerror
} |
{
  $NSBD postLength=$BATCHLENGTH -postUrl $POSTURLBASE/$BATCHUPDATE?$PACKAGE || pipeerror
} |
{
    if stopat "Batch update succeeded"
    then
	cat
    else
	pipeerror
	abort "batch update failed"
    fi
}

checkpipeerror
