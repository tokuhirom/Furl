#!perl -w
use strict;
use warnings;
use Test::Requires {
    'Plack::Request' => 0,
    'HTTP::Body'     => 0,
    Starlet          => 0.11
};
use Furl::HTTP;
use Test::TCP;
use Test::More;

use Starlet::Server;

my $n = shift(@ARGV) || 3;

my $host = '127.0.0.1';

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new();
        for (1 .. $n) {
            note "request/$_";
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    host       => $host,
                    port       => $port,
                    path_query => '/foo',
                );
            is $code, 200, "request()/$_";
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 4, 'header'
                or diag(explain($headers));
            is Furl::HTTP::_header_get($headers, 'Connection'), 'keep-alive'
                or diag(explain($headers));
            is $content, '/foo'
                or do{ require Devel::Peek; Devel::Peek::Dump($content) };

            ok defined( $furl->{connection_pool}->steal($host, $port) ), 'in keep-alive';
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        Starlet::Server->new(
            host               => $host,
            port               => $port,
            max_keepalive_reqs => 10,
        )->run(sub {
            my $env = shift;
            $env->{SERVER_PROTOCOL} = 'HTTP/1.0'; #force response HTTP/1.0
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}) ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);

