use strict;
use warnings;

use Furl::HTTP;
use IO::Socket::INET;
use Test::More;
use Test::TCP;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(timeout => 1);
        my (undef, $code, $msg) = $furl->request(
            method  => 'GET',
            host    => '127.0.0.1',
            port    => $port,
            path    => '/',
        );
        is $code, 500, "Should return 500 error on timeout while receiving";
        like $msg,
             qr/Internal Response: Cannot read content body: timeout/,
             "Should mention body read timeout";
    },
    server => sub {
        my $port = shift;
        my $listen_sock = IO::Socket::INET->new(
            Listen    => 5,
            LocalHost => '127.0.0.1',
            LocalPort => $port,
            ReuseAddr => 1,
        ) or die $!;
        local $SIG{PIPE} = 'IGNORE';
        my $is_skipped_test = 0;
        while (1) {
            my $sock = $listen_sock->accept or next;

            # Skip the first readiness probe connection from Test::TCP
            if (! $is_skipped_test) {
                close $sock;
                $is_skipped_test = 1;
                next;
            }

            sysread($sock, my $buf, 1048576, 0); # read request

            # send headers (no Content-Length)
            syswrite $sock, join(
                "\r\n",
                "HTTP/1.0 200 OK",
                "Content-Type: text/plain",
                "",
                "abcde",
            );
            sleep 3;
            close $sock;
        }
    },
);

done_testing;
