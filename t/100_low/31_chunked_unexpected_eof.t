use strict;
use warnings;

use Furl::HTTP;
use IO::Socket::INET;
use Test::More;
use Test::TCP;

my $chunk = "x"x1024;
my @res;
for ( 1..20) {
    push @res, '400', $chunk;
}

test_tcp(
    client => sub {
        my $port = shift;
        my (undef, $code, undef, undef, $body) = Furl::HTTP->new->request(
            method => 'GET',
            host   => '127.0.0.1',
            port   => $port,
            path   => '/',
        );
        is $code, 500, 'code';
        like $body, qr/Unexpected EOF/, 'body';
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
            my $n = syswrite $sock, join(
                "\r\n",
                "HTTP/1.1 200 OK",
                "Content-Type: text/plain",
                "Transfer-Encoding: chunked",
                "Connection: close",
                "",
                @res,
                "5",
            );
            close $sock;
        }
    },
);



done_testing;
