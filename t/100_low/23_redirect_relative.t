use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::Requires 'Plack';
use Plack::Loader;
use Test::More;
use Test::Requires 'URI';

use Plack::Request;

test_tcp(
    client => sub {
        my $port = shift;

        subtest 'redirect' => sub {
            my $furl = Furl::HTTP->new();
            my ( undef, $code, $msg, $headers, $content ) = $furl->request( url => "http://127.0.0.1:$port/foo/" );
            is $code, 200;
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 2;
            is $content, 'OK';
        };

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            my $req = Plack::Request->new($env);
            if ($env->{PATH_INFO} eq '/foo/bar') {
                return [ 200, [ 'Content-Length' => 2 ], ['OK'] ];
            } else {
                return [ 302, [ 'Location' => './bar', 'Content-Length' => 0 ],
                    [] ];
            }
        });
    }
);

