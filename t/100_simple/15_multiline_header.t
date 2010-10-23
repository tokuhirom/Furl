use strict;
use warnings;
use Furl;
use Test::TCP;
use Plack::Loader;
use Test::More;

use Plack::Request;
use File::Temp;
use Fcntl qw/:seek/;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new();

        my ( $status, $msg, $headers, $body ) =
          $furl->get( "http://127.0.0.1:$port/", [ 'X-Foo' => "bar\015\012baz" ] );
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
