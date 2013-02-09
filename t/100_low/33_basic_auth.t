use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
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
        done_testing;
    },
    server => sub {
        my $port = shift;
        t::HTTPServer->new(port => $port)->run(sub {;
            my $env = shift;
            is($env->{HTTP_AUTHORIZATION}, 'Basic ZGFua29nYWk6a29nYWlkYW4= ');
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}) ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);

