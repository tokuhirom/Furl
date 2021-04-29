use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack::Loader', 'Plack::Request';

use Plack::Loader;
use Plack::Request;

$ENV{LANG} = 'C';

test_tcp(
    client => sub {
        my $port = shift;

        subtest 'redirect' => sub {
            my $furl = Furl::HTTP->new();
            my ( undef, $code, $msg, $headers, $content ) =
            $furl->request( url => "http://127.0.0.1:$port/1", );
            is $code, 200;
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 2;
            is $content, 'OK';
        };

        subtest 'not enough redirect' => sub {
            my $furl = Furl::HTTP->new(max_redirects => 0);
            my ( undef, $code, $msg, $headers, $content ) =
            $furl->request( url => "http://127.0.0.1:$port/1", );
            is $code, 302;
            is $msg, 'Found';
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 0;
            is Furl::HTTP::_header_get($headers, 'Location'), "http://127.0.0.1:$port/2";
            is $content, '';
        };

        subtest 'over max redirect' => sub {
            my $max_redirects = 7;
            my $furl = Furl::HTTP->new(max_redirects => $max_redirects);
            my $start_num = 4;
            my ( undef, $code, $msg, $headers, $content ) =
            $furl->request( url => "http://127.0.0.1:$port/$start_num");
            is $code, 302, 'code ok';
            is $msg, 'Found', 'msg ok';
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 0, 'content length ok';
            is Furl::HTTP::_header_get($headers, 'Location'), "http://127.0.0.1:$port/" . ( $max_redirects + $start_num + 1 ), 'url ok';
            is $content, '', 'content ok';
        };

        subtest 'POST redirects' => sub {
            my $furl = Furl::HTTP->new();

            my ( undef, undef, undef, undef, $content ) =
            $furl->post("http://127.0.0.1:$port/301", [], "");
            is $content, 'POST', 'POST into 301 results in a POST';

            ( undef, undef, undef, undef, $content ) =
            $furl->post("http://127.0.0.1:$port/302", [], "");
            is $content, 'GET', 'POST into 302 is implemented as 303';

            ( undef, undef, undef, undef, $content ) =
            $furl->post("http://127.0.0.1:$port/303", [], "");
            is $content, 'GET', 'POST into 303 results in a GET';

            ( undef, undef, undef, undef, $content ) =
            $furl->post("http://127.0.0.1:$port/307", [], "");
            is $content, 'POST', 'POST into 307 results in a POST';

            ( undef, undef, undef, undef, $content ) =
            $furl->post("http://127.0.0.1:$port/308", [], "");
            is $content, 'POST', 'POST into 308 results in a POST';
        };

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            my $req = Plack::Request->new($env);
            $req->path_info =~ m{/(\d+)$} or die;
            my $id = $1;
            if ($id == 3) {
                return [ 200, [ 'Content-Length' => 2 ], ['OK'] ];
            } elsif ($id =~ /^3\d\d$/) {
                my $base = $req->base;
                $base->path("/200"); # redirect target, see below
                return [ $id, [ 'Location' => $base->as_string ] ];
            } elsif ($id == 200) {
                # redirect target, see above
                my $method = $req->method;
                return [ 200, [ 'Content-Length' => length $method ], [$method] ];
            } else {
                my $base = $req->base;
                $base->path('/' . ($id + 1));
                return [ 302, ['Location' => $base->as_string], []];
            }
        });
    }
);

