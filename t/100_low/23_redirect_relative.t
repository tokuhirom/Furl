use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;
use Test::Requires qw(Plack::Request HTTP::Body), 'URI';

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

        subtest 'redirect to root' => sub {
            my $furl = Furl::HTTP->new(max_redirects => 0);
            my ( undef, $code, $msg, $headers, $content ) = $furl->request( url => "http://127.0.0.1:$port/baz/" );
            is $code, 302;
            is $msg, "Found";
            is Furl::HTTP::_header_get($headers, 'location'), "/foo/";
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
            } elsif ($env->{PATH_INFO} eq '/baz/') {
                return [ 302, [ 'Location' => '/foo/', 'Content-Length' => 0 ],
                    [] ];
            } else {
                return [ 302, [ 'Location' => './bar', 'Content-Length' => 0 ],
                    [] ];
            }
        });
    }
);

