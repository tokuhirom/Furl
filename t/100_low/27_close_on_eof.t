use strict;
use warnings;

use Furl::HTTP;
use IO::Socket::INET;
use Test::More;
use Test::TCP;

test_tcp(
    client => sub {
        my $port = shift;
        my (undef, $code, undef, undef, $body) = Furl::HTTP->new->request(
            method => 'GET',
            host   => '127.0.0.1',
            port   => $port,
            path   => '/',
        );
        is $code, 200, 'code';
        is $body, 'abcde', 'body';
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
        while (1) {
            my $sock = $listen_sock->accept
                or next;
            sysread($sock, my $buf, 1048576, 0); # read request
            syswrite $sock, join(
                "\r\n",
                "HTTP/1.0 200 OK",
                "Content-Type: text/plain",
                "",
                "abcde",
            );
            close $sock;
        }
    },
);

done_testing;
