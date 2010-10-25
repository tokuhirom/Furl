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
SV* furl_newSVpvn_lc(const char* const pv, STRLEN const len) {
    dTHX;
    SV* const sv = sv_2mortal(newSV(len));
    STRLEN i;
    for(i = 0; i < len; i++) {
        SvPVX_mutable(sv)[i] = furl_tolower(pv[i]);
    }
    SvPOK_on(sv);
    SvCUR_set(sv, len);
    *SvEND(sv) = '\0';
    return sv;
}

MODULE = Furl PACKAGE = Furl

PROTOTYPES: DISABLE

void
parse_http_response(SV *buffer_sv, int last_len, HV* special_headers)
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
    size_t i;

    /* NOTE: ret is the number of bytes cosumed if successful,
     * -2 if request is partial,
     * -1 if failed. */

    EXTEND(SP, 4);
    mPUSHi(minor_version);
    mPUSHi(status);
    mPUSHp(msg, msg_len);
    mPUSHi(ret);
    for (i=0; i < num_headers; i++) {
        const char* const name     = headers_st[i].name;
        size_t const      name_len = headers_st[i].name_len;
        SV* const         namesv   = furl_newSVpvn_lc(name, name_len);
        SV* const         valuesv  = newSVpvn_flags(
            headers_st[i].value,
            headers_st[i].value_len,
            SVs_TEMP );
        HE* he;

        EXTEND(SP, 2);
        PUSHs(namesv);
        PUSHs(valuesv);

        he = hv_fetch_ent(special_headers, namesv, FALSE, 0U);
        if(he) {
            SV* const placeholder = hv_iterval(special_headers, he);
            SvSetMagicSV_nosteal(placeholder, valuesv);
        }
    }
}
