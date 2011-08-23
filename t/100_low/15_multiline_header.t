use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;

use Plack::Request;
use File::Temp;
use Fcntl qw/:seek/;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new();

        my ( undef, $status, $msg, $headers, $body ) =
          $furl->request( url => "http://127.0.0.1:$port/", headers => [ 'X-Foo' => "bar\015\012baz" ], method => 'GET' );
        is $status, 200;

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto( port => $port )->run(
            sub {
                my $req = Plack::Request->new(shift);
                is $req->header('X-Foo'), "bar  baz";
                return [ 200, [ 'Content-Length' => 2 ], ['OK'] ];
            }
        );
    }
);
