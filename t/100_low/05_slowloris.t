use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';

use Plack::Request;

use t::Slowloris;

my $n = shift(@ARGV) || 3;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new();
        for (1..$n) {
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                    headers    => [ "X-Foo" => "ppp" ]
                );
            is $code, 200, "request()/$_";
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 4;
            is $content, '/foo';
        }
        for (1..3) {
            my $path_query = '/bar?a=b;c=d&e=f';
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(url => "http://127.0.0.1:$port$path_query", method => 'GET');
            is $code, 200, "get()/$_";
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'),
                length($path_query);
            is $content, $path_query;
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        Slowloris::Server->new(port => $port)->run(sub {
            my $env = shift;
            is $env->{'HTTP_X_FOO'}, "ppp" if $env->{REQUEST_URI} eq '/foo';
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}) ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);

