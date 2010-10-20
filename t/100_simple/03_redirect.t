use strict;
use warnings;
use Furl;
use Test::TCP;
use Plack::Loader;
use Test::More;
use Plack::Util;
use Plack::Request;

test_tcp(
    client => sub {
        my $port = shift;

        subtest 'redirect' => sub {
            my $furl = Furl->new();
            my ( $code, $headers, $content ) =
            $furl->request( url => "http://127.0.0.1:$port/1", );
            is $code, 200;
            is Plack::Util::header_get($headers, 'Content-Length'), 2;
            is $content, 'OK';
        };

        subtest 'not enough redirect' => sub {
            my $furl = Furl->new(max_redirects => 0);
            my ( $code, $headers, $content ) =
            $furl->request( url => "http://127.0.0.1:$port/1", );
            is $code, 302;
            is Plack::Util::header_get($headers, 'Content-Length'), 0;
            is Plack::Util::header_get($headers, 'Location'), "http://127.0.0.1:$port/2";
            is $content, '';
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
            if ($id > 3) {
                return [ 200, [ 'Content-Length' => 2 ], ['OK'] ];
            } else {
                my $base = $req->base;
                $base->path('/' . ($id + 1));
                return [ 302, ['Location' => $base->as_string], []];
            }
        });
    }
);

