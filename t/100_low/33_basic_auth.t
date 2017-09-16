use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use Test::Requires 'URI::Escape';
use FindBin;
use lib "$FindBin::Bin/../..";
use t::HTTPServer;

my $n = shift(@ARGV) || 3;
test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(bufsize => 10, timeout => 3);
        for (1 .. $n) {
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    url => "http://dankogai:kogaidan\@127.0.0.1:${port}/foo",
                );
            is $code, 200, "request()/$_";
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 4, 'header'
                or diag(explain($headers));
            is $content, '/foo'
                or do{ require Devel::Peek; Devel::Peek::Dump($content) };
        }
        for ($n + 1 .. $n + $n) {
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    url => "http://dan%40kogai:kogai%2Fdan\@127.0.0.1:${port}/escape",
                );
            is $code, 200, "request()/$_";
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 7, 'header'
                or diag(explain($headers));
            is $content, '/escape'
                or do{ require Devel::Peek; Devel::Peek::Dump($content) };
        }

        done_testing;
    },
    server => sub {
        my $port = shift;
        my $basic = 'ZGFua29nYWk6a29nYWlkYW4=';
        t::HTTPServer->new(port => $port)->run(sub {;
            my $env = shift;
            if ($env->{REQUEST_URI} eq '/escape') {
                $basic = 'ZGFuQGtvZ2FpOmtvZ2FpL2Rhbg==';
            }
            is($env->{HTTP_AUTHORIZATION}, 'Basic ' . $basic);
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}) ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);

