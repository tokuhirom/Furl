#include "xshelper.h"
#include <curl/curl.h>
#include <curl/easy.h>
#include <string.h>

STATIC_INLINE
size_t furl_content_write(char *ptr, size_t size, size_t nmemb, void*stream) {
    dTHX;
    SV*buf = (SV*)stream;
    sv_catpvn(buf, ptr, size*nmemb);
    return size*nmemb;
}

STATIC_INLINE
size_t furl_header_write(char *ptr, size_t size, size_t nmemb, void*stream) {
    dTHX;
    AV*buf = (AV*)stream;
    av_push(buf, newSVpv(ptr, size*nmemb));
    return size*nmemb;
}

MODULE=Furl PACKAGE=Furl

BOOT:
    curl_global_init(0);

void
_new_curl(const char *agent, int timeout)
PPCODE:
    CURL * curl = curl_easy_init();
    curl_easy_setopt( curl, CURLOPT_USERAGENT,      agent );
    curl_easy_setopt( curl, CURLOPT_TIMEOUT,        timeout );
    curl_easy_setopt( curl, CURLOPT_HEADER,         0 );
    curl_easy_setopt( curl, CURLOPT_NOPROGRESS,     1 );
    curl_easy_setopt( curl, CURLOPT_WRITEFUNCTION,  furl_content_write );
    curl_easy_setopt( curl, CURLOPT_HEADERFUNCTION, furl_header_write );
    mXPUSHi(curl);
    XSRETURN(1);

void
_request(SV *curl_sv, const char * url, SV* headers, const char *method, const char *content, SV*tmpfile)
PPCODE:
    CURL * curl = (CURL*)SvIV(curl_sv);
    curl_easy_setopt( curl, CURLOPT_URL,        url );
    curl_easy_setopt( curl, CURLOPT_POSTFIELDS, content );
    curl_easy_setopt( curl, CURLOPT_CUSTOMREQUEST, method );
    struct curl_slist *header_slist = NULL;
    {
        AV *array = (AV *)SvRV(headers);
        int last = av_len(array);
        int i;

        for (i=0;i<=last;i++) {
            SV **sv = av_fetch(array,i,0);
            STRLEN len = 0;
            char *string = SvPV(*sv, len);
            if (len == 0) break;
            header_slist = curl_slist_append(header_slist, string);
        }
        header_slist = curl_slist_append(header_slist, "\015\012");

        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_slist);

    }
    SV* res_content = sv_2mortal(newSVpv("", 0));
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, res_content);

    AV* res_headers = newAV();
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, res_headers);

    CURLcode retcode = curl_easy_perform(curl);

    curl_slist_free_all(header_slist);
    EXTEND(SP, 3);
    if (retcode == 0) {
        long status;
        if (CURLE_OK != curl_easy_getinfo(curl, CURLINFO_HTTP_CODE, &status)) {
            croak("FATAL");
        }
        mPUSHs(newSViv(status));
        mPUSHs(newRV_inc((SV*)res_headers));
        PUSHs(res_content);
    } else {
        mPUSHi(500);
        mPUSHs(newRV_inc((SV*)res_headers));
        const char * errstr = curl_easy_strerror(retcode);
        mPUSHs(newSVpvn(errstr, strlen(errstr)));
    }
    XSRETURN(3);

