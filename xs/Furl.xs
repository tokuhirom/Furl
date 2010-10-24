#include "xshelper.h"
#include <string.h>
#include "picohttpparser/picohttpparser.h"
#include "picohttpparser/picohttpparser.c"

#define HEADER_CMP_WRAPPER(s1, s2, n1) furl_header_cmp(s1, s2, n1, sizeof(s2)-1)

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
        if (furl_tolower(*s1++) != *s2++) {
            return 0;
        }
    }
    return 1;
}

MODULE = Furl PACKAGE = Furl

PROTOTYPES: DISABLE

void
parse_http_response(SV *buffer_sv, int last_len)
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
    AV* const headers = newAV_mortal();
    size_t i;
    SV * content_length    = &PL_sv_undef;
    SV * connection        = &PL_sv_no; // as an empty string
    SV * location          = &PL_sv_no;
    SV * transfer_encoding = &PL_sv_no;
    SV * content_encoding  = &PL_sv_no;
    av_extend(headers, (num_headers - 1) * 2);
    for (i=0; i < num_headers; i++) {
        const char* const name     = headers_st[i].name;
        size_t const      name_len = headers_st[i].name_len;
        SV* const         namesv   = newSVpvn_flags(name, name_len, SVs_TEMP);
        SV* const         valuesv  = newSVpvn_flags(
            headers_st[i].value,
            headers_st[i].value_len,
            SVs_TEMP );
        if (HEADER_CMP_WRAPPER(name, "content-length", name_len)) {
            IV const clen = SvIV(valuesv);
            content_length = valuesv;
            /* TODO: more strict check using grok_number() */
            if (clen == IV_MIN || clen == IV_MAX) {
                croak("overflow or undeflow is found in Content-Length"
                    "(%"SVf")", valuesv);
            }
        } else if (HEADER_CMP_WRAPPER(name, "connection", name_len)) {
            connection = valuesv;
        } else if (HEADER_CMP_WRAPPER(name, "location", name_len)) {
            location = valuesv;
        } else if (HEADER_CMP_WRAPPER(name, "transfer-encoding", name_len)) {
            transfer_encoding = valuesv;
        } else if (HEADER_CMP_WRAPPER(name, "content-encoding", name_len)) {
            content_encoding = valuesv;
        }
        av_push(headers, SvREFCNT_inc_simple_NN(namesv));
        av_push(headers, SvREFCNT_inc_simple_NN(valuesv));
    }

    EXTEND(SP, 10);
    mPUSHi(minor_version);
    mPUSHi(status);
    mPUSHp(msg, msg_len);
    PUSHs(content_length);
    PUSHs(connection);
    PUSHs(location);
    PUSHs(transfer_encoding);
    PUSHs(content_encoding);
    mPUSHs(newRV_inc((SV*)headers));
    mPUSHi(ret);
    /* returns number of bytes cosumed if successful, -2 if request is partial,
     * -1 if failed */
}
