#!perl -w
use strict;
use warnings;
use Test::Requires qw(Starman);
use Furl::HTTP;
use Test::TCP;
use Test::More;

use t::SilentStarman;
#BEGIN{ $ENV{STARMAN_DEBUG} = 1 }

{
    package Timedout::Server;
    use base qw(Starman::Server);

    sub _finalize_response {
        my $self = shift;
        my $res  = $self->SUPER::_finalize_response(@_);
        close $self->{server}{client};
        return $res;
    }
}

my $n = shift(@ARGV) || 3;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new();
        for (1 .. $n) {
            note "request/$_";
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                );
            is $code, 200, "request()/$_";
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 4, 'header'
                or diag(explain($headers));
            is Furl::HTTP::_header_get($headers, 'Connection'), 'keep-alive';
            is $content, '/foo'
                or do{ require Devel::Peek; Devel::Peek::Dump($content) };
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        Timedout::Server->new(
        )->run(sub {
            my $env = shift;
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}) ],
                [$env->{REQUEST_URI}]
            ];
        }, {
            host      => '127.0.0.1',
            port      => $port,
            keepalive => 1,
        });
    }
);

