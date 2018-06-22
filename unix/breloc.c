/*
 * breloc -- binary relocate.  Replace all occurrences of the string "frompath"
 *   in the "file(s)" (which defaults to stdin) with the string "topath".  If
 *   "topath" is longer than "frompath" then there must be at least as many
 *   extra slashes in or after "frompath" in the file as the difference in
 *   length between them (plus one more if "topath" doesn't end in slash); on
 *   the other hand, if "topath" is shorter than "frompath" then padding
 *   slashes will be added to make up the difference.  Thus in general if
 *   binary packages are built with a configure "--prefix" with a lot of extra
 *   slashes, breloc can be used to relocate them.  The '-r' (reversible) flag
 *   restricts replacements to those that can be reversed if breloc is later
 *   applied with "topath" and "frompath" reversed: '-r' requires that extra
 *   slashes must be after the "frompath" in the file only, not within it, and
 *   also requires at least one slash after the "frompath" in the file unless
 *   both "frompath" and "topath" already end in a slash or are the same
 *   length.  The '-c' (collapse) flag collapses the padding slashes into
 *   a single one when it replaces them, shrinking the file size.
 */

/*
 * Copyright (C) 2000-2003 by Dave Dykstra and Lucent Technologies
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

char *brelocversion = "@(#)breloc 1.3	2002/01/31 Dave Dykstra";

#include <stdio.h>
#include <errno.h>

#ifndef NO_MAIN
#include <sys/types.h>
#include <sys/stat.h>
#include <signal.h>
#include <string.h>
#endif

#ifdef NO_MEMMOVE
#define memmove(S1, S2, N) bcopy(S2, S1, N)
#endif

#define ERR_WRITING 1
#define ERR_PADDING 2
#define ERR_SAVING 3

#define REVERSIBLE 1
#define COLLAPSE 2
#define BINARYFILE 4

#ifndef _USING_PROTOTYPES_
#ifdef __STDC__
#define _USING_PROTOTYPES_
#endif
#endif

#define MAXSAVESIZE	4095
unsigned char savebuf[MAXSAVESIZE+1];

int 	safe_flag = 0;

int
#ifdef _USING_PROTOTYPES_
overflow(int c, FILE *fin, FILE *fout, int (*callbp)(int, int))
#else
overflow(c, fin, fout, callbp)
int c;
FILE *fin;
FILE *fout;
int (*callbp());
#endif
{
    int i;

    if (callbp != NULL) {
	if ((*callbp)(ERR_SAVING, MAXSAVESIZE))
	    return(EOF);
	/* put out all remaining data unchecked because reading from stdin
	 * and don't want to truncate */
	for (i = 0; i < MAXSAVESIZE; i++)
	    putc(savebuf[i], fout);
	putc(c, fout);
	while ((c = getc(fin)) != EOF)
	    putc(c, fout);
    }
    return(EOF);
}

int
#ifdef _USING_PROTOTYPES_
brelocfile(FILE *fin, FILE *fout, unsigned char *fromp, unsigned char *top,
		    int flags, int (*callbp)(int, int))
#else
brelocfile(fin, fout, fromp, top, flags, callbp)
FILE *fin;
FILE *fout;
unsigned char *fromp;
unsigned char *top;
int flags;
int (*callbp());
#endif
{


/* The "goteof" flag avoids having to make savebuf be made of ints.
 * The "gotc" flag tells mysavec when it was a newly read character
 *   that needs to be saved in case need to back up in the input.
 */

#define mygetc()	((savep != endsavep) ? (gotc = 0, c = *savep++) \
				     : (goteof ? EOF : (gotc = 1, getc(fin))))

#define mysavec(c)	{if (c == EOF) goteof = 1; \
			else if (gotc) { \
			    if (savep == &savebuf[MAXSAVESIZE]) \
				return(overflow(c, fin, fout, callbp)); \
			    *savep++ = c; \
			    endsavep++; } }

#define myputc(c)	{if (putc(c,fout) == EOF) { \
			    if (callbp != NULL) (*callbp)(ERR_WRITING, errno); \
			    return(EOF); } }

    int goteof = 0, gotc;
    int c, i, fromlen, tolen, minextraslashes = 0, ret = 0;
    unsigned char *p, *endp, *savep = NULL, *endsavep = NULL;

    fromlen = strlen((char *) fromp);
    tolen = strlen((char *) top);
    if ((tolen > fromlen) && (top[tolen - 1] != '/')) {
	/* "to" is longer than "from" and doesn't end in slash so require an
	 *   extra padding slash to ensure continued separation of filename
	 *   components.
	 */
	minextraslashes = 1;

    } else if ((flags & REVERSIBLE) && (tolen != fromlen) &&
		!((fromp[fromlen - 1] == '/') && (top[tolen - 1] == '/'))) {
	/* If reversibility is required and the "to" and "from" aren't both
	 *   the same length and don't both end in '/', also require an extra
	 *   following slash.  If didn't do this, replacing a longer name that
	 *   didn't have any trailing slashes in the file by a shorter name,
	 *   for example:
	 *    $ echo 'V=${V:-/ab/cd}' | breloc /cd=/c
	 *    V=${V:-/ab/c/}
	 *   would not be able to be reversed:
	 *    $ echo 'V=${V:-/ab/cd}' | breloc /cd=/c | breloc /c=/cd
	 *    breloc: not enough slashes after /c in stdin, needed 2
	 * This is because breloc does not know whether or not the following
	 *   character is a separator, which the closing curly bracket in the
	 *   above example is to sh, so it has to always require an extra 
	 *   slash when tolen > fromlen and "to" doesn't end in slash.
	 */
	minextraslashes = 1;
    }
    while(1)
    {
	c = mygetc();
	if (c == EOF)
	    break;

	if (c == '\0')
	    flags |= BINARYFILE;

	if (c != *fromp) {
	    /* Haven't matched first character, just put it out & continue */
	    myputc(c);
	    continue;
	}

	/* matched first character */
	endp = fromp + fromlen;
	p = fromp;

	if (savep == endsavep) {
	    /* initialize pointers for saving input in case need to go back */
	    savep = endsavep = &savebuf[1];
	} else {
	    /* move already saved data down to the beginning of buffer
	     * in case need to read more after this
	     */
	    i = endsavep - savep;
	    memmove(&savebuf[1], savep, i);
	    savep = &savebuf[1];
	    endsavep = savep + i;
	}
	savebuf[0] = c;

	while(1)
	{
	    /* At this point matched from fromp up to and including p */

	    if (++p != endp)
	    {
		/* look at next character */
		c = mygetc();
		mysavec(c);
		if (c == *p) {
		    /* matching so far */
		    continue;
		}

		if (!(flags & REVERSIBLE) && (c == '/') && (*(p-1) == '/')) {
		    /* also accept extra slashes at any point unless
		     *   need to be able to reverse replacement
		     */
		    --p;
		    continue;
		}
nomatch:
		/* Didn't get a match. Send on first byte, set up to
		 * look at rest of already-read data again, and proceed.
		 */
		myputc(savebuf[0]);
		savep = &savebuf[1];
		break;
	    }
	    else
	    {
		/* Reached end of "from".  Now look for padding slashes. */
		int matchlen = savep - &savebuf[0];
		int slashesneeded = tolen - matchlen;
		int slasheseaten;

		if (slashesneeded <= 0) {
		    /* require at least one slash at end of "from" */
		    slashesneeded = minextraslashes;
		} else {
		    /* Require one more slash than strictly needed for
		     *   difference in length, to avoid losing a slash that
		     *   separates path components when tolen is one more
		     *   than fromlen.
		     */
		    slashesneeded += minextraslashes;
		}
		for (i = slashesneeded; i > 0; i--) {
		    c = mygetc();
		    mysavec(c);
		    if (c != '/')
			break;
		}
		if (i > 0) {
		    /* Didn't get enough slashes. */
		    if (callbp != NULL) {
			if ((*callbp)(ERR_PADDING, slashesneeded))
			    return(EOF);
			if ( safe_flag ) {
			    ret = EOF;
			}
		    }
		    /* Treat it like any other non-match */
		    goto nomatch;
		}

		/* A complete match.
		 * Put out replacement.
		 */
		if (ret != EOF)
		    ret++;
		for (i = 0; i < tolen; i++) {
		    c = *(top+i);
		    myputc(c);
		}

		/* throw away saved data */
		savep = endsavep = &savebuf[0];

		/* Put out padding if needed.
		 */
		slasheseaten = matchlen - tolen + slashesneeded;
		if (!(flags & COLLAPSE)) {
		    /* put out padding slashes */
		    for (i = slasheseaten; i > 0; i--) {
			myputc('/');
		    }
		} else {
		    /* put out at most one separating slash */
		    if (c == '/') {
			/* "to" ended in slash, already put it out */
			c = mygetc();
		    } else if (minextraslashes == 1) {
			/* already got it but haven't put it out */
			slasheseaten--;
			myputc('/');
			c = mygetc();
		    } else {
			/* haven't got it yet */
			c = mygetc();
			if (c == '/') {
			    myputc(c);
			    c = mygetc();
			}
		    }

		    while (c == '/') {
			/* eat the rest of the slashes */
			slasheseaten++;
			c = mygetc();
		    }

		    if (flags & BINARYFILE) {
			/* Put out the rest of the string including its
			 *   terminating null, then one less than as many
			 *   slashes as we've eaten, then another null.
			 */
			while (c != '\0') {
			    myputc(c);
			    c = mygetc();
			}
			myputc('\0');
			if (slasheseaten > 0) {
			    for (i = slasheseaten-1; i > 0; i--) {
				myputc('/');
			    }
			    myputc('\0');
			}
		    } else {
			/* save the extra non-slash character */
			mysavec(c);
			savep = &savebuf[0];
		    }
		}
		break;
	    }
	}
    }

    return(ret);
}


#ifndef NO_MAIN
void
usage()
{
    fprintf(stderr, "Usage: breloc [-rcv] frompath=topath [file ...]\n");
    fprintf(stderr, "  If no file name given, defaults to stdin/stdout\n");
    fprintf(stderr, "  Otherwise if there are changes replaces file in place\n");
    fprintf(stderr, "  -r restricts replacements to those that can be reversed\n");
    fprintf(stderr, "  -c collapses multiple slashes in replaced paths (shrinking the file size)\n");
    fprintf(stderr, "  -v verbosely prints number of replacements to stderr\n");
    fprintf(stderr, "  -s safe - make it an error if any replacements are not possible\n");
    exit(2);
}

static char *infname;
static char *outfname;
static char *fromstr;

#ifndef RETSIGTYPE
#define RETSIGTYPE void
#endif

RETSIGTYPE
#ifdef _USING_PROTOTYPES_
cleanup(int sig)
#else
cleanup(sig)
int sig;
#endif
{
    if (outfname != NULL) {
	unlink(outfname);
    }
    exit(sig);
}

int
#ifdef _USING_PROTOTYPES_
backfunc(int errtype, int arg)
#else
backfunc(errtype, arg)
int errtype;
int arg;
#endif
{
    static char *lastwarned = NULL;

    switch(errtype)
    {
    case ERR_WRITING:
	errno = arg;
	perror(outfname);
	return(1);
    case ERR_PADDING:
	if (lastwarned != infname) {
	    lastwarned = infname;
	    fprintf(stderr, "breloc: %s: not enough slashes after '%s' in %s, needed %d\n", 
		( safe_flag == 0 ? "warning" : "error" ), 
		fromstr, infname, arg);
	}
	/* If reading from stdin, or if "safe" mode isn't requested, we
	 * return 0 (success)
	 */
	if ( (strcmp(infname, "stdin") == 0) || (safe_flag == 0) ) {
	    return(0);
	}
	return(1);
    case ERR_SAVING:
	fprintf(stderr,
	    "breloc: matching pattern in %s longer than max of %d\n",
			infname, arg);
	if (strcmp(infname, "stdin") == 0)
	    return(0);
	return(1);
    }
    return(0);
}

void
#ifdef _USING_PROTOTYPES_
printverbose(char *fname, int num, unsigned char *fromp, unsigned char *top)
#else
printverbose(fname, num, fromp, top)
char *fname;
int num;
unsigned char *fromp;
unsigned char *top;
#endif
{
    char *colon;
    if (*fname) 
	colon = ": ";
    else
	colon = "";
    if (num == 0)
	fprintf(stderr, "%s%sno occurrences of '%s'\n", fname, colon, fromp);
    else
	fprintf(stderr, "%s%s%d occurrences of '%s' replaced with '%s'\n",
		fname, colon, num, fromp, top);
}

int
#ifdef _USING_PROTOTYPES_
main(int argc, char **argv)
#else
main(argc, argv)
int argc;
char **argv;
#endif
{
    unsigned char *p, *fromp, *top;
    FILE *fin, *fout;
    struct stat statb;
    int ret = 0, verbose = 0, flags = 0, num;

    ++argv;
    --argc;

    while ((argc >= 1) && ((*argv)[0] == '-')) {
	for (p = (unsigned char *) &((*argv)[1]); *p; p++) {
	    switch (*p)
	    {
		case 'r':
		    flags |= REVERSIBLE;
		    break;
		case 'c':
		    flags |= COLLAPSE;
		    break;
		case 'v':
		    verbose = 1;
		    break;
	        case 's':
		    safe_flag = 1;
		    break;
		default:
		    usage();
	    }
	}
	++argv;
	--argc;
    }

    if (argc < 1) {
	usage();
    }

    if ((flags & REVERSIBLE) && (flags & COLLAPSE)) {
	fprintf(stderr, "breloc: -r and -c are conflicting options\n");
	exit(2);
    }

    /* split first arg into frompath and topath pieces, removing backslashes */

    fromp = (unsigned char *) *argv;
    for (p = fromp; *p; p++) {
	if (*p == '\\')
	    p++;
	if (*p == '=') {
	    break;
	}
	*fromp++ = *p;
    }

    if (*p != '=') {
	usage();
    }

    *p++ = '\0';

    fromp = p; /* temporary, will set top here ultimately */

    for (top = ++p; *p; p++) {
	if (*p == '\\') {
	    p++;
	}
	*top++ = *p;
    }
    *top = '\0';

    top = fromp;
    fromp = (unsigned char *) *argv;
    fromstr = (char *) fromp;

    if (argc == 1) {
	infname = "stdin";
	outfname = "stdout";
	if ((num = brelocfile(stdin, stdout, fromp, top, flags, backfunc)) == EOF)
	    return(1);
	if (verbose) {
	    printverbose("", num, fromp, top);
	}
	return(0);
    }

    if (signal(SIGHUP, cleanup) == SIG_IGN)
	signal(SIGHUP, SIG_IGN);
    if (signal(SIGINT, cleanup) == SIG_IGN)
	signal(SIGINT, SIG_IGN);
    if (signal(SIGTERM, cleanup) == SIG_IGN)
	signal(SIGTERM, SIG_IGN);
    if (signal(SIGPIPE, cleanup) == SIG_IGN)
	signal(SIGPIPE, SIG_IGN);

    while (--argc) {
	++argv;

	if ((fin = fopen(*argv, "r")) == NULL) {
	    perror(*argv);
	    ret = 1;
	    continue;
	}
	infname = *argv;
	outfname = (char *) malloc(strlen(*argv) + sizeof(".brelocNNNNNNNNNN"));
	strcpy(outfname, *argv);
	if (fstat(fileno(fin), &statb) == -1) {
	    strcat(outfname, " fstat");
	    perror(outfname);
	    fclose(fin);
	    free(outfname);
	    ret = 1;
	    continue;
	}
	if ((p = (unsigned char *) strrchr(outfname, '/')) == NULL) 
	    p = (unsigned char *) outfname;
	else
	    p++;
	sprintf((char *) p, ".breloc%d", getpid());
	if ((fout = fopen(outfname, "w")) == NULL) {
	    perror(outfname);
	}
	else {
	    chmod(outfname, 0600); /* just in case data is sensitive */
	    if ((num = brelocfile(fin, fout, fromp, top, flags, backfunc)) == EOF) {
		unlink(outfname);
		ret = 1;
	    }
	    else {
		if (num == 0) {
		    unlink(outfname);
		}
		else {
		    chmod(outfname, statb.st_mode);
#ifdef __CYGWIN__
		/* On cygwin, the unlink of infname works, but we can't
		 * rename outfname if fin is still open 
		 */
		    fclose(fin);
#endif
		    unlink(infname);
		    link(outfname, infname);
		    unlink(outfname);
		}
		if (verbose)
		    printverbose(infname, num, fromp, top);
	    }
	    fclose(fout);
	}
	fclose(fin);
	free(outfname);
	outfname = NULL;
    }

    return(ret);
}
#endif /* NO_MAIN */
