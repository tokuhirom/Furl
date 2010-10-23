#include "xshelper.h"
#include <string.h>
#include "picohttpparser/picohttpparser.h"
#include "picohttpparser/picohttpparser.c"

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
    IV content_length      = -1;
    SV * connection        = &PL_sv_no; // as an empty string
    SV * location          = &PL_sv_no;
    SV * transfer_encoding = &PL_sv_no;
    SV * content_encoding = &PL_sv_no;
    av_extend(headers, (num_headers - 1) * 2);
    for (i=0; i < num_headers; i++) {
        const char* const name     = headers_st[i].name;
        size_t const      name_len = headers_st[i].name_len;
        SV* const         namesv   = newSVpvn_flags(name, name_len, SVs_TEMP);
        SV* const         valuesv  = newSVpvn_flags(
            headers_st[i].value,
            headers_st[i].value_len,
            SVs_TEMP );
        /* TODO:strncasecmp is not portable */
        if (strncasecmp(name, "Content-Length", name_len) == 0) {
            content_length = SvIV(valuesv);
            /* TODO: more strict check using grok_number() */
            if (content_length == IV_MIN || content_length == IV_MAX) {
                croak("overflow or undeflow is found in Content-Length"
                    "(%"SVf")", valuesv);
            }
        } else if (strncasecmp(name, "Connection", name_len) == 0) {
            connection = valuesv;
        } else if (strncasecmp(name, "Location", name_len) == 0) {
            location = valuesv;
        } else if (strncasecmp(name, "Transfer-Encoding", name_len) == 0) {
            transfer_encoding = valuesv;
        } else if (strncasecmp(name, "Content-Encoding", name_len) == 0) {
            content_encoding = valuesv;
        }
        av_push(headers, SvREFCNT_inc_simple_NN(namesv));
        av_push(headers, SvREFCNT_inc_simple_NN(valuesv));
    }

    EXTEND(SP, 10);
    mPUSHi(minor_version);
    mPUSHi(status);
    mPUSHp(msg, msg_len);
    mPUSHi(content_length);
    PUSHs(connection);
    PUSHs(location);
    PUSHs(transfer_encoding);
    PUSHs(content_encoding);
    mPUSHs(newRV_inc((SV*)headers));
    mPUSHi(ret);
    /* returns number of bytes cosumed if successful, -2 if request is partial,
     * -1 if failed */
}
