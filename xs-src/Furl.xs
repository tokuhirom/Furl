#include "xshelper.h"
#include <string.h>
#include "picohttpparser/picohttpparser.h"

struct furl_headers {
    long content_length;
    SV * connection;
    struct phr_header headers[1024];
    size_t num_headers;
};

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
    struct furl_headers *headers_st;
    Newxz(headers_st, 1, struct furl_headers);
    headers_st->num_headers = sizeof(headers_st->headers) / sizeof(headers_st->headers[0]);
    int ret = phr_parse_response(buf, len, &minor_version, &status, &msg, &msg_len,  headers_st->headers, &(headers_st->num_headers), last_len);
    size_t i;
    headers_st->content_length = -1;
    SV * connection = &PL_sv_undef;
    for (i=0; i<headers_st->num_headers; i++) {
        /* TODO:strncasecmp is not portable */
        struct phr_header * h = &(headers_st->headers[i]);
        if (h->name_len > 5 && (h->name)[0] == 'C') {
            if (strncasecmp(h->name, "Content-Length", h->name_len) == 0) {
                char * buf;
                Newxz(buf, h->value_len+1, char);
                memcpy(buf, h->value, h->value_len);
                headers_st->content_length = strtol(buf, NULL, 10);
                Safefree(buf);
                if ((headers_st->content_length == LONG_MIN || headers_st->content_length == LONG_MAX) && errno==ERANGE) {
                    croak("overflow or undeflow is found in Content-Length");
                }
            }
            if (strncasecmp(h->name, "Connection", h->name_len) == 0) {
                connection = sv_2mortal(newSVpv(h->value, h->value_len));
            }
        }
    }

    SV *headers_obj = sv_2mortal(newRV_inc(sv_2mortal(newSViv((IVTYPE)headers_st))));
    sv_bless(headers_obj, gv_stashpv("Furl::Headers",TRUE));

    EXTEND(SP, 6);
    mPUSHi(minor_version);
    mPUSHi(status);
    mPUSHi(headers_st->content_length);
    PUSHs(connection);
    PUSHs(headers_obj);
    mPUSHi(ret);
    /* returns number of bytes cosumed if successful, -2 if request is partial,
     * -1 if failed */
    XSRETURN(6);

MODULE=Furl PACKAGE=Furl::Headers

void
content_length(SV *self)
PPCODE:
    struct furl_headers * headers = (struct furl_headers*)SvIV(SvRV(self));
    ST(0) = newSViv(headers->content_length);
    XSRETURN(1);

void
header(SV*self, const char*key)
PPCODE:
    struct furl_headers * headers = (struct furl_headers*)SvIV(SvRV(self));
    int c=0;
    size_t i;
    for (i=0; i < headers->num_headers; i++) {
        struct phr_header * h = &(headers->headers[i]);
        if (strncasecmp(key, h->name, h->name_len) == 0) {
            ++c;
            mXPUSHp(h->value, h->value_len);
            if (GIMME_V != G_ARRAY) {
                XSRETURN(c);
            }
        }
    }
    XSRETURN(c);

void
_keys(SV*self)
PPCODE:
    struct furl_headers * headers = (struct furl_headers*)SvIV(SvRV(self));
    size_t i;
    for (i=0; i < headers->num_headers; i++) {
        struct phr_header * h = &(headers->headers[i]);
        mXPUSHp(h->name, h->name_len);
    }
    XSRETURN(headers->num_headers);

#include "picohttpparser/picohttpparser.c"
