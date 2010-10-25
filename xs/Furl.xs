#define NEED_newSVpvn_flags
#define NEED_sv_2pv_flags
#include "xshelper.h"
#include <string.h>
#include "picohttpparser/picohttpparser.h"
#include "picohttpparser/picohttpparser.c"

/* I don't want to use tolower(3) since HTTP parser should not mention the locale. */
STATIC_INLINE
char furl_tolower(char c) {
    return ('A' <= c && c <= 'Z') ? (c - ('A' - 'a')) : c;
}

STATIC_INLINE
SV* furl_newSVpvn_lc(pTHX_ const char* const pv, STRLEN const len) {
    SV* const sv  = sv_2mortal(newSV(len));
    char* const d = SvPVX_mutable(sv);
    STRLEN i;
    for(i = 0; i < len; i++) {
        d[i] = furl_tolower(pv[i]);
    }
    SvPOK_on(sv);
    SvCUR_set(sv, len);
    *SvEND(sv) = '\0';
    return sv;
}

MODULE = Furl PACKAGE = Furl

PROTOTYPES: DISABLE

void
parse_http_response(SV *buffer_sv, int last_len, SV* headers_ref, HV* special_headers)
PPCODE:
{
    dXSTARG;
    STRLEN len;
    const char * const buf = SvPV_const(buffer_sv, len);
    int minor_version;
    int status;
    const char *msg;
    size_t msg_len;
    struct phr_header headers_st[128];
    size_t num_headers = sizeof(headers_st) / sizeof(headers_st[0]);
    int const ret = phr_parse_response(buf, len,
        &minor_version,
        &status,
        &msg, &msg_len,
        headers_st, &num_headers, last_len);
    SV* headers;
    size_t i;

    if(!(SvROK(headers_ref) && (
               SvTYPE(SvRV(headers_ref)) == SVt_PVHV
            || SvTYPE(SvRV(headers_ref)) == SVt_PVAV))) {
        croak("headers_ref must be a HASH or ARRAY reference");
    }
    headers = SvRV(headers_ref);

    /* NOTE: ret is the number of bytes cosumed if successful,
     * -2 if request is partial,
     * -1 if failed. */

    sv_setpvn(TARG, msg, msg_len);

    EXTEND(SP, 4);
    mPUSHi(minor_version);
    mPUSHi(status);
    PUSHs(TARG); /* message */
    mPUSHi(ret);
    for (i=0; i < num_headers; i++) {
        const char* const name     = headers_st[i].name;
        if (!name) { /* NULL if multiline header value */
                /* current implementation just ignore multiline header value. */
                /* TODO: better implementation is required. But it's not my job. */
                continue;
        }

        size_t const      name_len = headers_st[i].name_len;
        SV* const         namesv   = furl_newSVpvn_lc(aTHX_ name, name_len);
        SV* const         valuesv  = newSVpvn_flags(
            headers_st[i].value,
            headers_st[i].value_len,
            SVs_TEMP );
        HE* he;

        he = hv_fetch_ent(special_headers, namesv, FALSE, 0U);
        if(he) {
            SV* const placeholder = hv_iterval(special_headers, he);
            SvSetMagicSV_nosteal(placeholder, valuesv);
        }

        if(SvTYPE(headers) == SVt_PVAV) {
            av_push((AV*)headers, SvREFCNT_inc_simple_NN(namesv));
            av_push((AV*)headers, SvREFCNT_inc_simple_NN(valuesv));
        }
        else {
            (void)hv_store_ent((HV*)headers, namesv,
                SvREFCNT_inc_simple_NN(valuesv), 0U);
        }
    }
}
