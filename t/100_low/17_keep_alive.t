use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use t::HTTPServer;

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
        my $furl = Furl::HTTP->new(connection_pool => MyConnPool->new());
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
        t::HTTPServer->new( port => $port )->run(
            sub {
                my $env = shift;
                return [
                    200,
                    [  ],
                    [ 'OK' x 100 ]
                ];
            }
        );
    }
);

