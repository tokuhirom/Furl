#include "xshelper.h"
#include <string.h>
#include "picohttpparser/picohttpparser.h"

MODULE=Furl PACKAGE=Furl

void
parse_http_response(SV *buffer_sv, int last_len)
PPCODE:
    STRLEN len;
    char * buf = SvPV(buffer_sv, len);

    int minor_version;
    int status;
    const char *msg;
    size_t msg_len = 0;
    struct phr_header headers_st[1024];
    size_t num_headers = sizeof(headers_st) / sizeof(headers_st[0]);
    int ret = phr_parse_response(buf, len, &minor_version, &status, &msg, &msg_len,  headers_st, &num_headers, last_len);
    AV * headers = newAV();
    size_t i;
    for (i=0; i<num_headers; i++) {
        av_push(headers, newSVpv(headers_st[i].name, headers_st[i].name_len));
        av_push(headers, newSVpv(headers_st[i].value, headers_st[i].value_len));
    }

    EXTEND(SP, 3);
    mPUSHi(status);
    mPUSHs(newRV_inc((SV*)headers));
    mPUSHi(ret);
    /* returns number of bytes cosumed if successful, -2 if request is partial,
     * -1 if failed */
    XSRETURN(3);

#include "picohttpparser/picohttpparser.c"
