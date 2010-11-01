use strict;
use warnings;
use Test::TCP;
use Test::More;
use Furl::HTTP;
use t::HTTPServer;

my $s = q{The quick brown fox jumps over the lazy dog.\n};

my $chunk = sprintf qq{%x;foo=bar;baz="qux"\015\012%s\015\012},
    length($s), $s;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(bufsize => 80);
        for my $i(1, 3, 1024) {
            note "-- TEST (packets: $i)";
            my ( undef, $code, $msg, $headers, $content ) = $furl->request(
                port => $port,
                path => '/',
                host => '127.0.0.1',
                headers => ['X-Packet-Size', $i],
            );
            is $code, 200, 'status';
            is $content, $s x $i, 'content';
        }
        done_testing;
    },
    server => sub {
        my $port = shift;

        t::HTTPServer->new( port => $port, enable_chunked => 0 )->run(
            sub {
                my $env = shift;
                my $size = $env->{HTTP_X_PACKET_SIZE} or die '???';
                return [
                    200,
                    [ 'Transfer-Encoding' => 'chunked' ],
                    [ $chunk x $size, "0", "\015\012" x 2 ]
                ];
            }
        );
    }
);

