/*
 * Unix C routines for NSBD to interface with Tcl.
 * File created by Dave Dykstra <dwd@bell-labs.com>, 01 Nov 1996
 */
/*
 * Copyright (C) 1996-2003 by Dave Dykstra and Lucent Technologies
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *  
 * If those terms are not sufficient for you, contact the author to
 * discuss the possibility of an alternate license.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
#include <tcl.h>
#include <time.h>
#include <stdio.h>
#include <signal.h>
#ifdef STDC_HEADERS
#include <stdlib.h>
#include <string.h>
#else
#include <malloc.h>
#endif
#include <grp.h>
#include <utime.h>
#include <errno.h>

static Tcl_Interp *nsbd_interp;

RETSIGTYPE
#ifdef _USING_PROTOTYPES_
catch_nsbdsig(int sig)
#else
catch_nsbdsig(sig)
    int sig;
#endif
{
    char cmd[80];

    sprintf(cmd, "nsbdExitCleanup; exit %d", sig);
    Tcl_Eval(nsbd_interp, cmd);
}

static void
#ifdef _USING_PROTOTYPES_
setsigs(Tcl_Interp *interp)
#else
setsigs(interp)
    Tcl_Interp *interp;
#endif
{
    nsbd_interp = interp;

    if (signal(SIGHUP, catch_nsbdsig) == SIG_IGN)
	signal(SIGHUP, SIG_IGN);
    if (signal(SIGINT, catch_nsbdsig) == SIG_IGN)
	signal(SIGINT, SIG_IGN);
    if (signal(SIGTERM, catch_nsbdsig) == SIG_IGN)
	signal(SIGTERM, SIG_IGN);
    if (signal(SIGPIPE, catch_nsbdsig) == SIG_IGN)
	signal(SIGPIPE, SIG_IGN);
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_startTk(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_startTk(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
#ifdef WITHOUT_TK
    interp->result = "compiled without TK";
    return TCL_ERROR;
#else
#ifdef STANDALONE
    if (Tk_InitStandAlone(interp) == TCL_ERROR)
	return TCL_ERROR;
    Tcl_StaticPackage(interp, "Tk", Tk_InitStandAlone,
				(Tcl_PackageInitProc *) NULL);
    return TCL_OK;
#else
    static char loadtk[] = {
    /* At least on tcl7.5, the default auto_path when run non-interactively */
    /*   for some strange reason only includes lib/tcl7.5, not lib itself */
    "global auto_path\n\
    if {[lsearch $auto_path [file dirname [info library]]] < 0} {\n\
	lappend auto_path [file dirname [info library]]\n\
     }\n\
     package require Tk"
    };

    if (Tk_Init(interp) == TCL_ERROR)
	return TCL_ERROR;

    return Tcl_Eval(interp, loadtk);
#endif
#endif
}

void
#ifdef _USING_PROTOTYPES_
nsbdTclfree(char *blockPtr)
#else
nsbdTclfree(blockPtr)
    char *blockPtr;
#endif
{
    free(blockPtr);
}

static int
#ifdef _USING_PROTOTYPES_
nsbderror(Tcl_Interp *interp)
#else
nsbderror(interp)
    Tcl_Interp *interp;
#endif
{
    Tcl_SetErrorCode(interp, "NSBD", "INTERNAL", (char *) NULL);
    return TCL_ERROR;
}

#if !HAVE_STRERROR
char *
#ifdef _USING_PROTOTYPES_
strerror(int errcode)
#else
strerror(errcode)
	int errcode;
#endif
{
	extern int sys_nerr;
	extern char *sys_errlist[];

	if (errcode < 0 || errcode > sys_nerr)
		return("Unknown error");
	else
		return(sys_errlist[errcode]);
}
#else
extern char * strerror _ANSI_ARGS_((int errcode));
#endif

static int
#ifdef _USING_PROTOTYPES_
nsbd_primitiveSymLink(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_primitiveSymLink(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    if (argc != 3) {
	interp->result = "wrong # args: should be \"primitiveSymLink fromFile toFile\"";
	return TCL_ERROR;
    }
    if (symlink(argv[1], argv[2]) == -1) {
	char *errmsg = malloc(strlen(argv[1]) + strlen(argv[2]) +
				strlen(strerror(errno)) + 100);
	sprintf(errmsg, "cannot symLink %s %s: %s",
				argv[1], argv[2], strerror(errno));
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_primitiveHardLink(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_primitiveHardLink(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    if (argc != 3) {
	interp->result = "wrong # args: should be \"primitiveHardLink fromFile toFile\"";
	return TCL_ERROR;
    }
    if (link(argv[1], argv[2]) == -1) {
	char *errmsg = malloc(strlen(argv[1]) + strlen(argv[2]) +
				strlen(strerror(errno)) + 100);
	sprintf(errmsg, "cannot hardLink %s %s: %s",
				argv[1], argv[2], strerror(errno));
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_primitiveChangeMode(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_primitiveChangeMode(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    int mode;
    char *msg = NULL;

    if (argc != 3) {
	interp->result = "wrong # args: should be \"primitiveChangeMode path mode\"";
	return TCL_ERROR;
    }
    if (sscanf(argv[2], "%o", &mode) != 1) {
	msg = "second parameter not octal number";
    } else if (chmod(argv[1], mode) == -1) {
	msg = strerror(errno);
    }
    if (msg != NULL) {
	char *errmsg = malloc(strlen(argv[1]) + strlen(argv[2]) +
				strlen(msg) + 100);
	sprintf(errmsg, "cannot changeMode %s %s: %s", argv[1], argv[2], msg);
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
getGroupIdFromName(char *groupname)
#else
getGroupIdFromName(groupname)
    char *groupname;
#endif
{
    static int lastgid = -1;
    static char lastgroupname[100];

    if (strcmp(groupname, lastgroupname) != 0) {
	/* cache the group name/id for next time */
	struct group *grp = getgrnam(groupname);
	if (grp == NULL)
	    return(-1);
	lastgid = grp->gr_gid;
	strncpy(lastgroupname, groupname, sizeof(lastgroupname) - 1);
    }
    return(lastgid);
}

static char *
#ifdef _USING_PROTOTYPES_
getGroupNameFromId(int gid)
#else
getGroupNameFromId(gid)
    int gid;
#endif
{
    static int lastgid = -1;
    static char lastgroupname[100];

    if (gid != lastgid) {
	/* cache the group name/id for next time */
	struct group *grp = getgrgid(gid);
	if (grp == NULL)
	    return(NULL);
	lastgid = gid;
	strncpy(lastgroupname, grp->gr_name, sizeof(lastgroupname) - 1);
    }
    return(lastgroupname);
}


static int
#ifdef _USING_PROTOTYPES_
nsbd_getGroupIdFromName(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_getGroupIdFromName(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    int gid;
    char *errmsg;

    if (argc != 2) {
	interp->result = "wrong # args: should be \"getGroupIdFromName group\"";
	return TCL_ERROR;
    }

    gid = getGroupIdFromName(argv[1]);
    if (gid < 0) {
	errmsg = malloc(strlen(argv[1]) + 100);
	sprintf(errmsg, "getGroupIdFromName cannot getgrnam %s", argv[1]);
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    sprintf(interp->result, "%d", gid);
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_getGroupNameFromId(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_getGroupNameFromId(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    int gid;
    char *groupname;
    char *errmsg;

    if (argc != 2) {
	interp->result = "wrong # args: should be \"getGroupNameFromId gid\"";
	return TCL_ERROR;
    }

    gid = -1;
    sscanf(argv[1], "%d", &gid);
    groupname = getGroupNameFromId(gid);
    if (groupname == NULL) {
	errmsg = malloc(strlen(argv[1]) + 100);
	sprintf(errmsg, "getGroupNameFromId cannot getgrgid %s", argv[1]);
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    strcpy(interp->result, groupname);
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_primitiveChangeGroup(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_primitiveChangeGroup(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    static int uid = -1;
    int gid;
    char *msg = NULL, *errmsg;

    if (argc != 3) {
	interp->result = "wrong # args: should be \"primitiveChangeGroup path group\"";
	return TCL_ERROR;
    }
    if (uid == -1) {
	/* some operating systems do not permit a -1 as the owner parameter */
	/*  of chown to leave it alone, so get it once and save it */
	uid = getuid();
    }
    gid = getGroupIdFromName(argv[2]);
    if (gid < 0) {
	errmsg = malloc(strlen(argv[2]) + 100);
	sprintf(errmsg, "changeGroup cannot getGroupIdFromName %s", argv[2]);
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    if (chown(argv[1], uid, gid) == -1) {
	msg = strerror(errno);
    }
    if (msg != NULL) {
	errmsg = malloc(strlen(argv[1]) + strlen(argv[2]) + strlen(msg) + 100);
	sprintf(errmsg, "cannot changeGroup %s %s: %s", argv[1], argv[2], msg);
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_primitiveChangeMtime(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_primitiveChangeMtime(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    struct utimbuf buf;
    char *msg = NULL;

    if (argc != 3) {
	interp->result = "wrong # args: should be \"primitiveChangeMtime path utime\"";
	return TCL_ERROR;
    }
    if (sscanf(argv[2], "%d", &buf.modtime) != 1) {
	msg = "second parameter not a number";
    } else {
	/* to be really correct should also do a stat and restore the     */
	/* access time, or update it to now, but be lazy and use mod time */
	buf.actime = buf.modtime;
	if (utime(argv[1], &buf) == -1) {
	    msg = strerror(errno);
	}
    }
    if (msg != NULL) {
	char *errmsg = malloc(strlen(argv[1]) + strlen(argv[2]) +
				strlen(msg) + 100);
	sprintf(errmsg, "cannot changeMtime %s %s: %s", argv[1], argv[2], msg);
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_umask(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_umask(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    int mask;

    if (argc != 2) {
	interp->result = "wrong # args: should be \"umask mask_in_octal\"";
	return TCL_ERROR;
    }
    if (sscanf(argv[1], "%o", &mask) != 1) {
	char *errmsg = malloc(strlen(argv[1]) + 100);
	sprintf(errmsg, "cannot scan umask %s", argv[1]);
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    if (umask(mask) == -1) {
	char *errmsg = malloc(strlen(argv[1]) + strlen(strerror(errno)) + 100);
	sprintf(errmsg, "cannot set umask %s: %s", argv[1], strerror(errno));
	interp->freeProc = nsbdTclfree;
	interp->result = errmsg;
	return (nsbderror(interp));
    }
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_stdinisatty(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_stdinisatty(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    if (argc != 1) {
	interp->result = "wrong # args: should be \"stdinisatty\"";
	return TCL_ERROR;
    }
    sprintf(interp->result, "%d", isatty(0));
    return TCL_OK;
}

/*
 * nsbdnestlevel is here for speed when parsing large files;  it was 
 *   measured to be about 4 times faster than the tcl version on tcl8.0a2
 *   on a file of about 10000 lines; the tcl version took up about half
 *   the parse time of that file, and this C version made it drop to
 *   about 1/5th of the total parse time.
 * nsbdnestlevel figures out the nestlevel in a line of an "nsbd" file.
 * parameters are
 *    1. line - the line to parse
 *    2. linelength - the number of bytes in the line
 *    3. lineno - the line number that is being parsed
 * returns list of two items: the nesting level and the number of characters
 *    of whitespace at the beginning of the line
 */

#define MAXNESTLEVEL 50
static int nestlength[MAXNESTLEVEL+1];
static int nestlevel;

static int
#ifdef _USING_PROTOTYPES_
nsbd_nestlevelInit(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_nestlevelInit(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    nestlevel = 0;
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_nestlevel(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_nestlevel(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    char *line, *lineno;
    int linelength;
    int nlength = 0, whitechars = 0;
    int i, c;
    int curlength; 

    if (argc != 4) {
	interp->result = "wrong # args: should be \"nsbdnestlevel line linelength lineno\"";
	return TCL_ERROR;
    }
    
    line = argv[1];
    sscanf(argv[2], "%d", &linelength);
    lineno = argv[3];
    c = 0;
    for (i = 0; i < linelength; i++) {
	if ((c = line[i]) == ' ') {
	    nlength++;
	    whitechars++;
	}
	else if (c == '\t') {
	    nlength += 8 - (nlength % 8);
	    whitechars++;
	}
	else {
	    break;
	}
    }
    if ((c != '#') && (whitechars != linelength)) {
	curlength = nestlength[nestlevel];
	if (nlength != curlength) {
	    if (nlength > curlength) {
		if (++nestlevel >= MAXNESTLEVEL) {
		    sprintf(interp->result,
			    "nesting level too deep at line %s", lineno);
		    return (nsbderror(interp));
		}
		nestlength[nestlevel] = nlength;
	    }
	    else {
		/* must be less, find out which if any previous level matches */
		nestlevel--;
		while ((nestlevel > 0) && (nlength < nestlength[nestlevel])) {
		    nestlevel--;
		}
		if (nlength != nestlength[nestlevel]) {
		    sprintf(interp->result,
			"invalid indent level on line %s", lineno);
		    return(nsbderror(interp));
		}
	    }
	}
    }
    sprintf(interp->result, "%d %d", nestlevel, whitechars);
    return TCL_OK;
}

static int
#ifdef _USING_PROTOTYPES_
nsbd_matchpatterns(ClientData clientData, Tcl_Interp *interp, int argc, char *argv[])
#else
nsbd_matchpatterns(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    char *pat1, *pat2, *end1, *end2;
    int result;
    char *wildcards = "*?[]\\";

    if (argc != 3) {
	interp->result = "wrong # args: should be \"matchpatterns pat1 pat2\"";
	return TCL_ERROR;
    }
    pat1 = argv[1];
    pat2 = argv[2];
    if ((strpbrk(pat1, wildcards) == NULL) &&
				(strpbrk(pat2, wildcards) == NULL)) {
	sprintf(interp->result, "%d", strcmp(pat1, pat2) == 0);
	return TCL_OK;
    }
    end1 = pat1;
    end2 = pat2;
    result = 0;
    while (1) {
	/* find the next '/' in both patterns */
	while (*end1 && (*end1 != '/')) {
	    end1++;
	}
	while (*end2 && (*end2 != '/')) {
	    end2++;
	}
	if ((*pat1 == '*') || (*pat2 == '*')) {
	    /* match any any component in the other pattern */
	    if (((*pat1 == '*') && !*end1) || ((*pat2 == '*') && !*end2)) {
		/* at end of one, match all of the rest */
		result = 1;
		break;
	    }
	} else {
	    char endc1, endc2;
	    int match;
	    endc1 = *end1;
	    *end1 = '\0';
	    endc2 = *end2;
	    *end2 = '\0';
	    match = (strcmp(pat1, pat2) == 0) || Tcl_StringMatch(pat1, pat2) ||
			Tcl_StringMatch(pat2, pat1);
	    *end1 = endc1;
	    *end2 = endc2;
	    if (!match) {
		break;
	    }
	}
	if (!*end1 || !*end2) {
	    /* reached the end of one of the patterns */
	    if (!*end1 && !*end2) {
	        /* reached the end of both */
		result = 1;
	    }
	    break;
	}
	/* move forward to the next component */
	pat1 = end1 + 1;
	pat2 = end2 + 1;
	end1 = pat1;
	end2 = pat2;
    }
    sprintf(interp->result, "%d", result);
    return TCL_OK;
}

#ifdef STANDALONE
#define Tcl_Init Tcl_InitStandAlone
#endif

int
#ifdef _USING_PROTOTYPES_
nsbd_init(Tcl_Interp *interp)
#else
nsbd_init(interp)
    Tcl_Interp *interp;
#endif
{
    if (Tcl_Init(interp) == TCL_ERROR)
	return TCL_ERROR;
    setsigs(interp);

#ifdef STANDALONE
    if (Tcl_Eval(interp, "set nsbdStandAlone 1") == TCL_ERROR) {
	return TCL_ERROR;
    }
#endif
    /* Tclgdbm_Init(interp); */
    Tclmd5_Init(interp);
    Tclsha1_Init(interp);

    Tcl_CreateCommand(interp, "startTk", nsbd_startTk,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "primitiveSymLink", nsbd_primitiveSymLink,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "primitiveHardLink", nsbd_primitiveHardLink,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "primitiveChangeMode", nsbd_primitiveChangeMode,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "getGroupIdFromName", nsbd_getGroupIdFromName,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "getGroupNameFromId", nsbd_getGroupNameFromId,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "primitiveChangeGroup", nsbd_primitiveChangeGroup,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "primitiveChangeMtime", nsbd_primitiveChangeMtime,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "umask", nsbd_umask,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "stdinisatty", nsbd_stdinisatty,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "nsbdnestlevelInit", nsbd_nestlevelInit,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "nsbdnestlevel", nsbd_nestlevel,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "matchpatterns", nsbd_matchpatterns,
	(ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);

    return TCL_OK;
}

/*
 * being called from tcl2c and a tcl installation with plus patch
 */
int
#ifdef _USING_PROTOTYPES_
nsbd_initStandAlone(Tcl_Interp *interp)
#else
nsbd_initStandAlone(interp)
    Tcl_Interp *interp;
#endif
{
    return(nsbd_init(interp));
}


#ifdef WRAP

int
#ifdef _USING_PROTOTYPES_
main(int argc, char **argv)
#else
main(argc, argv)
int argc;
char **argv;
#endif
{
    return (Wrap_Main(argc, argv, nsbd_init, Tcl_CreateInterp()));
}

#endif
