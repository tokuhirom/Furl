use strict;
use warnings;
use Furl;
use Test::TCP;
use Plack::Loader;
use Test::More;

use Plack::Request;

test_tcp(
    client => sub {
        my $port = shift;

        subtest 'redirect' => sub {
            my $furl = Furl->new();
            my ( $code, $msg, $headers, $content ) =
            $furl->request( url => "http://127.0.0.1:$port/1", );
            is $code, 200;
            is $msg, "OK";
            is Furl::Util::header_get($headers, 'Content-Length'), 2;
            is $content, 'OK';
        };

        subtest 'not enough redirect' => sub {
            my $furl = Furl->new(max_redirects => 0);
            my ( $code, $msg, $headers, $content ) =
            $furl->request( url => "http://127.0.0.1:$port/1", );
            is $code, 302;
            is $msg, 'Found';
            is Furl::Util::header_get($headers, 'Content-Length'), 0;
            is Furl::Util::header_get($headers, 'Location'), "http://127.0.0.1:$port/2";
            is $content, '';
        };

        subtest 'over max redirect' => sub {
            my $max_redirects = 7;
            my $furl = Furl->new(max_redirects => $max_redirects);
            my $start_num = 4;
            my ( $code, $msg, $headers, $content ) =
            $furl->request( url => "http://127.0.0.1:$port/$start_num");
            is $code, 302, 'code ok';
            is $msg, 'Found', 'msg ok';
            is Furl::Util::header_get($headers, 'Content-Length'), 0, 'content length ok';
            is Furl::Util::header_get($headers, 'Location'), "http://127.0.0.1:$port/" . ( $max_redirects + $start_num + 1 ), 'url ok';
            is $content, '', 'content ok';
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
            } else {
                my $base = $req->base;
                $base->path('/' . ($id + 1));
                return [ 302, ['Location' => $base->as_string], []];
            }
        });
    }
);

