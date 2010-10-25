#include "xshelper.h"
#include <string.h>
#include "picohttpparser/picohttpparser.h"
#include "picohttpparser/picohttpparser.c"

/* I don't want to use tolower(3) since HTTP parser should not mention the locale. */
STATIC_INLINE
char furl_tolower(char c) {
    return ('A' <= c && c <= 'Z') ? (c - 'A' + 'a') : c;
}

STATIC_INLINE
int furl_header_cmp(const char * s1, const char * s2, int n1, int n2) {
    int i;
    if (n1!=n2) {
        return 0;
    }

    for (i=0; i<n1; i++) {
        if (furl_tolower(*s1++) != furl_tolower(*s2++)) {
            return 0;
        }
    }
    return 1;
}

MODULE = Furl PACKAGE = Furl

PROTOTYPES: DISABLE

void
parse_http_response(SV *buffer_sv, int last_len, ...)
PPCODE:
{
    STRLEN len;
    const char * const buf = SvPV_const(buffer_sv, len);
    int minor_version;
    int status;
    const char *msg;
    size_t msg_len;
    struct phr_header headers_st[512];
    size_t num_headers = sizeof(headers_st) / sizeof(headers_st[0]);
    int const ret = phr_parse_response(buf, len,
        &minor_version,
        &status,
        &msg, &msg_len,
        headers_st, &num_headers, last_len);
    AV* const headers         = newAV_mortal();
    AV* const special_headers = newAV_mortal();
    size_t i;
    av_extend(headers, (num_headers - 1) * 2);
    av_extend(special_headers, items-2);
    for (i=0; i < num_headers; i++) {
        const char* const name     = headers_st[i].name;
        size_t const      name_len = headers_st[i].name_len;
        SV* const         namesv   = newSVpvn_flags(name, name_len, SVs_TEMP);
        SV* const         valuesv  = newSVpvn_flags(
            headers_st[i].value,
            headers_st[i].value_len,
            SVs_TEMP );
        int j;

        av_push(headers, SvREFCNT_inc_simple_NN(namesv));
        av_push(headers, SvREFCNT_inc_simple_NN(valuesv));

        /* linear search for special headers */
        for (j=2; j<items; j++) {
            STRLEN key_len;
            const char *const key = SvPV_const(ST(j), key_len);
            if (furl_header_cmp(name, key, name_len, key_len)) {
                av_store(special_headers, j-2, SvREFCNT_inc_simple_NN(valuesv));
                break;
            }
        }
    }

    EXTEND(SP, 5 + (items-2));
    mPUSHi(minor_version);
    mPUSHi(status);
    mPUSHp(msg, msg_len);
    mPUSHs(newRV_inc((SV*)headers));
    /* ret is the number of bytes cosumed if successful,
     * -2 if request is partial,
     * -1 if failed. */
    mPUSHi(ret);
    /* special headers are returned as a list */
    for (i=0; i<(size_t)items-2; i++) {
        PUSHs( AvARRAY(special_headers)[i] );
    }
}
