/* definitions extracted from sha1.c by Dave Dykstra, 4/22/97 */

/* use tcl.h to get _ANSI_ARGS_ definition */
#include "tcl.h"

typedef struct {
    unsigned long state[5];
    unsigned long count[2];
    unsigned char buffer[64];
} SHA1_CTX;

void SHA1Init _ANSI_ARGS_((SHA1_CTX* context));
void SHA1Update _ANSI_ARGS_((SHA1_CTX* context, unsigned char* data, unsigned int len));
void SHA1Final _ANSI_ARGS_((unsigned char digest[20], SHA1_CTX* context));
