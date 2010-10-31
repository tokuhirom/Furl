use strict;
use warnings;
use Test::Requires 'Starman';
use Furl::HTTP;
use Test::TCP;
use Plack::Loader;
use Test::More;

use Plack::Request;
use t::SilentStarman;

my($add_conn_cache, $remove_conn_cache) = (0, 0);
{
    package Test::Furl::HTTP;
    our @ISA = qw(Furl::HTTP);

    sub add_conn_cache    { $add_conn_cache++ }
    sub remove_conn_cache { $remove_conn_cache++ }
}

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Test::Furl::HTTP->new();
        for (1 .. 3) {
            note "-- TEST $_";
            my ( undef, $code, $msg, $headers, $content ) =
            $furl->request(
                port => $port,
                path => '/',
                host => '127.0.0.1',
            );
            is $code, 200;
            is $content, 'OK' x 100;
        }
        is $add_conn_cache,    3;
        is $remove_conn_cache, 0;

        $add_conn_cache    = 0;
        $remove_conn_cache = 0;

        $furl->request(
            method => 'HEAD',
            port => $port,
            path => '/',
            host => '127.0.0.1',
        );
        is $add_conn_cache,    0, 'HEAD forces to close connections';
        is $remove_conn_cache, 1;
        done_testing;
    },
    server => sub {
        my $port = shift;
        my $starmn = Plack::Loader->load( 'Starman',
            host          => '127.0.0.1',
            port          => $port,
            log_level     => 0,
            'max-workers' => 1,
        )->run(
            sub {
                my $env = shift;
                return [
                    200,
                    [ 'Transfer-Encoding' => 'chunked' ],
                    [ 'OK'x100 ]
                ];
            }
          );
    }
);

