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
        # some httpd(e.g. ASP.NET) returns 00000000 as chunked end.
        for my $chunk_end (qw(0 00000000)) {
            for my $i(1, 3, 1024) {
                note "-- TEST (packets: $i)";
                my ( undef, $code, $msg, $headers, $content ) = $furl->request(
                    port => $port,
                    path => '/',
                    host => '127.0.0.1',
                    headers => ['X-Packet-Size', $i, 'X-Chunck-End' => $chunk_end],
                );
                is $code, 200, 'status';
                is $content, $s x $i, 'content';
            }
        }
        done_testing;
    },
    server => sub {
        my $port = shift;

        t::HTTPServer->new( port => $port, enable_chunked => 0 )->run(
            sub {
                my $env = shift;
                my $size = $env->{HTTP_X_PACKET_SIZE} or die '???';
                my $end_mark = $env->{HTTP_X_CHUNCK_END};
                return [
                    200,
                    [ 'Transfer-Encoding' => 'chunked' ],
                    [ $chunk x $size, $end_mark, "\015\012" x 2 ]
                ];
            }
        );
    }
);

