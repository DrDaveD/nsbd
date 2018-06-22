#ifndef MD5_H
#define MD5_H

/* use tcl.h to get _ANSI_ARGS_ definition */
#include "tcl.h"

/*
 * The following defines are to change the name of the main MD5 routines
 * so there's no chance of picking them up from other libraries.  This
 * caused a problem on Solaris 5.3 system while using auto loading from tclsh.
 * This is especially important because the parameters to MD5Final are 
 * different than in the RSA implementation.
 * - Dave Dykstra, 12/19/96
 */
#define MD5Init TCLMD5Init
#define MD5Update TCLMD5Update
#define MD5Final TCLMD5Final

#ifdef __alpha
typedef unsigned int uint32;
#else
typedef unsigned long uint32;
#endif

struct MD5Context {
	uint32 buf[4];
	uint32 bits[2];
	unsigned char in[64];
};

void MD5Init _ANSI_ARGS_((struct MD5Context *context));
void MD5Update _ANSI_ARGS_((struct MD5Context *context, unsigned char const *buf,
	       unsigned len));
void MD5Final _ANSI_ARGS_((unsigned char digest[16], struct MD5Context *context));
void MD5Transform _ANSI_ARGS_((uint32 buf[4], uint32 const in[16]));

/*
 * This is needed to make RSAREF happy on some MS-DOS compilers.
 */
typedef struct MD5Context MD5_CTX;

#endif /* !MD5_H */
