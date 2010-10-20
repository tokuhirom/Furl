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
    ssize_t content_length = -1;
    SV * connection = &PL_sv_undef;
    SV * location = &PL_sv_undef;
    for (i=0; i<num_headers; i++) {
        /* TODO:strncasecmp is not portable */
        if (strncasecmp(headers_st[i].name, "Content-Length", headers_st[i].name_len) == 0) {
            char * buf;
            Newxz(buf, headers_st[i].value_len+1, char);
            memcpy(buf, headers_st[i].value, headers_st[i].value_len);
            content_length = strtol(buf, NULL, 10);
            Safefree(buf);
            if ((content_length == LONG_MIN || content_length == LONG_MAX) && errno==ERANGE) {
                croak("overflow or undeflow is found in Content-Length");
            }
        } else if (strncasecmp(headers_st[i].name, "Connection", headers_st[i].name_len) == 0) {
            connection = sv_2mortal(newSVpv(headers_st[i].value, headers_st[i].value_len));
        } else if (strncasecmp(headers_st[i].name, "Location", headers_st[i].name_len) == 0) {
            location = sv_2mortal(newSVpv(headers_st[i].value, headers_st[i].value_len));
        }
        av_push(headers, newSVpv(headers_st[i].name, headers_st[i].name_len));
        av_push(headers, newSVpv(headers_st[i].value, headers_st[i].value_len));
    }

    EXTEND(SP, 7);
    mPUSHi(minor_version);
    mPUSHi(status);
    mPUSHi(content_length);
    PUSHs(connection);
    PUSHs(location);
    mPUSHs(newRV_inc((SV*)headers));
    mPUSHi(ret);
    /* returns number of bytes cosumed if successful, -2 if request is partial,
     * -1 if failed */
    XSRETURN(7);

#include "picohttpparser/picohttpparser.c"
