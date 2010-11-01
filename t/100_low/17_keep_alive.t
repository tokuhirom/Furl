use strict;
use warnings;
use Test::Requires 'Starman';
use Furl::HTTP;
use Test::TCP;
use Plack::Loader;
use Test::More;

use Plack::Request;
use t::SilentStarman;

my ($stealed, $pushed) = (0, 0);
{
    package MyConnPool;
    sub new { bless [], shift }
    sub steal { $stealed++; undef }
    sub push  { $pushed++;  undef }
}

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(conn_pool => MyConnPool->new());
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
        is $stealed, 3, 'stealed';
        is $pushed,  3;

        $pushed  = 0;
        $stealed = 0;

        $furl->request(
            method => 'HEAD',
            port => $port,
            path => '/',
            host => '127.0.0.1',
        );
        is $pushed, 0, 'HEAD forces to close connections';
        is $stealed, 1;
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

