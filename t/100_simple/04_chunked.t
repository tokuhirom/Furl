use strict;
use warnings;
use Test::Requires 'Starman';
use Furl;
use Test::TCP;
use Plack::Loader;
use Test::More;

use Plack::Request;

test_tcp(
    port => 1119,
    client => sub {
        my $port = shift;
        my $furl = Furl->new(bufsize => 80);
        for (1..3) {
            note "-- TEST $_";
            my ( $code, $msg, $headers, $content ) =
            $furl->request(
                port => $port,
                path => '/',
                host => '127.0.0.1',
                headers => [ "X-Foo" => "ppp" ]
            );
            is $code, 200;
            is $content, 'OK' x 140;
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->load( 'Starman',
            host          => '127.0.0.1',
            port          => $port,
            'max-workers' => 1,
        )->run(
            sub {
                my $env = shift;
                my $req = Plack::Request->new($env);
                is $req->header('X-Foo'), "ppp";
                return [
                    200,
                    [ 'Transfer-Encoding' => 'chunked' ],
                    [ 'OK'x100, 'OK'x40 ]
                ];
            }
          );
    }
);

