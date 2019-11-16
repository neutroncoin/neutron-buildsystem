#include <openssl/bn.h>
#include <openssl/ecdsa.h>
#include <openssl/opensslv.h>

BIGNUM *ECDSA_SIG_getr(const ECDSA_SIG *sig)
{
    const BIGNUM *r;
    ECDSA_SIG_get0(sig, &r, NULL);
    return (BIGNUM *) r;
}

BIGNUM *ECDSA_SIG_gets(const ECDSA_SIG *sig)
{
    const BIGNUM *s;
    ECDSA_SIG_get0(sig, NULL, &s);
    return (BIGNUM *) s;
}
