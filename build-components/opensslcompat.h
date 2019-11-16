#ifndef OPENSSH_COMPAT
#define OPENSSH_COMPAT

#include <openssl/bn.h>
#include <openssl/ecdsa.h>

extern "C" BIGNUM *ECDSA_SIG_getr(const ECDSA_SIG *sig);
extern "C" BIGNUM *ECDSA_SIG_gets(const ECDSA_SIG *sig);

#endif
