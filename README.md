# NAME

Furl - Lightning-fast URL fetcher

# SYNOPSIS

    use Furl;

    my $furl = Furl->new(
        agent   => 'MyGreatUA/2.0',
        timeout => 10,
    );

    my $res = $furl->get('http://example.com/');
    die $res->status_line unless $res->is_success;
    print $res->content;

    my $res = $furl->post(
        'http://example.com/', # URL
        [...],                 # headers
        [ foo => 'bar' ],      # form data (HashRef/FileHandle are also okay)
    );

    # Accept-Encoding is supported but optional
    $furl = Furl->new(
        headers => [ 'Accept-Encoding' => 'gzip' ],
    );
    my $body = $furl->get('http://example.com/some/compressed');

# DESCRIPTION

Furl is yet another HTTP client library. LWP is the de facto standard HTTP
client for Perl 5, but it is too slow for some critical jobs, and too complex
for weekend hacking. Furl resolves these issues. Enjoy it!

# INTERFACE

## Class Methods

### `Furl->new(%args | \%args) :Furl`

Creates and returns a new Furl client with _%args_. Dies on errors.

_%args_ might be:

- agent :Str = "Furl/$VERSION"
- timeout :Int = 10
- max\_redirects :Int = 7
- capture\_request :Bool = false

    If this parameter is true, [Furl::HTTP](http://search.cpan.org/perldoc?Furl::HTTP) captures raw request string.
    You can get it by `$res->captured_req_headers` and `$res->captured_req_content`.

- proxy :Str
- no\_proxy :Str
- headers :ArrayRef

## Instance Methods

### `$furl->request([$request,] %args) :Furl::Response`

Sends an HTTP request to a specified URL and returns a instance of [Furl::Response](http://search.cpan.org/perldoc?Furl::Response).

_%args_ might be:

- scheme :Str = "http"

    Protocol scheme. May be `http` or `https`.

- host :Str

    Server host to connect.

    You must specify at least `host` or `url`.

- port :Int = 80

    Server port to connect. The default is 80 on `scheme => 'http'`,
    or 443 on `scheme => 'https'`.

- path\_query :Str = "/"

    Path and query to request.

- url :Str

    URL to request.

    You can use `url` instead of `scheme`, `host`, `port` and `path_query`.

- headers :ArrayRef

    HTTP request headers. e.g. `headers => [ 'Accept-Encoding' => 'gzip' ]`.

- content : Str | ArrayRef\[Str\] | HashRef\[Str\] | FileHandle

    Content to request.

If the number of arguments is an odd number, this method assumes that the
first argument is an instance of `HTTP::Request`. Remaining arguments
can be any of the previously describe values (but currently there's no
way to really utilize them, so don't use it)

    my $req = HTTP::Request->new(...);
    my $res = $furl->request($req);

You can also specify an object other than HTTP::Request (e.g. Furl::Request),
but the object must implement the following methods:

- uri
- method
- content
- headers

These must return the same type of values as their counterparts in
`HTTP::Request`.

You must encode all the queries or this method will die, saying
`Wide character in ...`.

### `$furl->get($url :Str, $headers :ArrayRef[Str] )`

This is an easy-to-use alias to `request()`, sending the `GET` method.

### `$furl->head($url :Str, $headers :ArrayRef[Str] )`

This is an easy-to-use alias to `request()`, sending the `HEAD` method.

### `$furl->post($url :Str, $headers :ArrayRef[Str], $content :Any)`

This is an easy-to-use alias to `request()`, sending the `POST` method.

### `$furl->put($url :Str, $headers :ArrayRef[Str], $content :Any)`

This is an easy-to-use alias to `request()`, sending the `PUT` method.

### `$furl->delete($url :Str, $headers :ArrayRef[Str] )`

This is an easy-to-use alias to `request()`, sending the `DELETE` method.

### `$furl->env_proxy()`

Loads proxy settings from `$ENV{HTTP_PROXY}` and `$ENV{NO_PROXY}`.

# FAQ

- Does Furl depends on XS modules?

    No. Although some optional features require XS modules, basic features are
    available without XS modules.

    Note that Furl requires HTTP::Parser::XS, which seems an XS module
    but includes a pure Perl backend, HTTP::Parser::XS::PP.

- I need more speed.

    See [Furl::HTTP](http://search.cpan.org/perldoc?Furl::HTTP), which provides the low level interface of [Furl](http://search.cpan.org/perldoc?Furl).
    It is faster than `Furl.pm` since [Furl::HTTP](http://search.cpan.org/perldoc?Furl::HTTP) does not create response objects.

- How do you use cookie\_jar?

    Furl does not directly support the cookie\_jar option available in LWP. You can use [HTTP::Cookies](http://search.cpan.org/perldoc?HTTP::Cookies), [HTTP::Request](http://search.cpan.org/perldoc?HTTP::Request), [HTTP::Response](http://search.cpan.org/perldoc?HTTP::Response) like following.

        my $f = Furl->new();
        my $cookies = HTTP::Cookies->new();
        my $req = HTTP::Request->new(...);
        $cookies->add_cookie_header($req);
        my $res = H$f->request_with_http_request($req)->as_http_response;
        $res->request($req);
        $cookies->extract_cookies($res);
        # and use $res.

- How do you limit the response content length?

    You can limit the content length by callback function.

        my $f = Furl->new();
        my $content = '';
        my $limit = 1_000_000;
        my %special_headers = ('content-length' => undef);
        my $res = $f->request(
            method          => 'GET',
            url             => $url,
            special_headers => \%special_headers,
            write_code      => sub {
                my ( $status, $msg, $headers, $buf ) = @_;
                if (($special_headers{'content-length'}||0) > $limit || length($content) > $limit) {
                    die "over limit: $limit";
                }
                $content .= $buf;
            }
        );

- How do you display the progress bar?

        my $bar = Term::ProgressBar->new({count => 1024, ETA => 'linear'});
        $bar->minor(0);
        $bar->max_update_rate(1);

        my $f = Furl->new();
        my $content = '';
        my %special_headers = ('content-length' => undef);;
        my $did_set_target = 0;
        my $received_size = 0;
        my $next_update  = 0;
        $f->request(
            method          => 'GET',
            url             => $url,
            special_headers => \%special_headers,
            write_code      => sub {
                my ( $status, $msg, $headers, $buf ) = @_;
                unless ($did_set_target) {
                    if ( my $cl = $special_headers{'content-length'} ) {
                        $bar->target($cl);
                        $did_set_target++;
                    }
                    else {
                        $bar->target( $received_size + 2 * length($buf) );
                    }
                }
                $received_size += length($buf);
                $content .= $buf;
                $next_update = $bar->update($received_size)
                if $received_size >= $next_update;
            }
        );
- HTTPS requests claims warnings!

    When you make https requests, IO::Socket::SSL may complain about it like:

        *******************************************************************
         Using the default of SSL_verify_mode of SSL_VERIFY_NONE for client
         is depreciated! Please set SSL_verify_mode to SSL_VERIFY_PEER
         together with SSL_ca_file|SSL_ca_path for verification.
         If you really don't want to verify the certificate and keep the
         connection open to Man-In-The-Middle attacks please set
         SSL_verify_mode explicitly to SSL_VERIFY_NONE in your application.
        *******************************************************************

    You should set `SSL_verify_mode` explicitly with Furl's `ssl_opts`.

        use IO::Socket::SSL;

        my $ua = Furl->new(
            ssl_opts => {
                SSL_verify_mode => SSL_VERIFY_PEER(),
            },
        });

    See [IO::Socket::SSL](http://search.cpan.org/perldoc?IO::Socket::SSL) for details.

# AUTHOR

Tokuhiro Matsuno <tokuhirom@gmail.com>

Fuji, Goro (gfx)

# THANKS TO

Kazuho Oku

mala

mattn

lestrrat

walf443

lestrrat

audreyt

# SEE ALSO

[LWP](http://search.cpan.org/perldoc?LWP)

[IO::Socket::SSL](http://search.cpan.org/perldoc?IO::Socket::SSL)

[Furl::HTTP](http://search.cpan.org/perldoc?Furl::HTTP)

[Furl::Response](http://search.cpan.org/perldoc?Furl::Response)

# LICENSE

Copyright (C) Tokuhiro Matsuno.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
