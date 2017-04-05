use strict;
use warnings;
use Test::More;
use Furl::HTTP;
use Test::TCP;
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
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                    content    => '',
                );
            is $code, 200, "request()/$_";
            is $msg, "OK";
        }

        done_testing;
    },
    server => sub {
        my $port = shift;
        t::HTTPServer->new(port => $port)->run(sub {;
            my $env = shift;
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}) ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);


