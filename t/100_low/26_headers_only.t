use strict;
use warnings;
use HTTP::Parser::XS qw(parse_http_request);
use IO::Socket::INET;
use Test::More;
use Furl::HTTP;
use Test::TCP;

my $n = shift(@ARGV) || 3;
test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(
            bufsize => 10,
            timeout => 3,
        );
        for my $req_code (qw(100 199 204 304)) {
            for (1 .. $n) {
                my (undef, $code, $msg, $headers, $content) = $furl->request(
                    port       => $port,
                    path_query => "/$req_code",
                    host       => '127.0.0.1',
                );
                is $code, $req_code, "$msg";
                is $content, '';
            }
        }
    },
    server => sub {
        my $port = shift;
        my $listen_sock = IO::Socket::INET->new(
            Listen    => 5,
            LocalHost => '127.0.0.1',
            LocalPort => $port,
            ReuseAddr => 1,
        ) or die $!;
    MAIN_LOOP:
        while (1) {
            my $sock = $listen_sock->accept
                or next;
            my $buf = '';
            my %env;
        PARSE_HTTP_REQUEST:
            while (1) {
                my $nread = sysread(
                    $sock, $buf, 1048576, length($buf));
                $buf =~ s!^(\015\012)*!!;
                if (! defined $nread) {
                    die "cannot read HTTP request header: $!";
                }
                if ($nread == 0) {
                    # unexpected EOF while reading HTTP request header
                    warn "received a broken HTTP request";
                    next MAIN_LOOP;
                }
                my $ret = parse_http_request($buf, \%env);
                if ($ret == -2) {    # incomplete.
                    next;
                }
                elsif ($ret == -1) {    # request is broken
                    die "broken HTTP header";
                }
                else {
                    $buf = substr($buf, $ret);
                    last PARSE_HTTP_REQUEST;
                }
            }
            my $code = $env{PATH_INFO} =~ m{^/([0-9]+)$} ? $1 : 200;
            print $sock '', << "EOT";
HTTP/1.0 $code love\r
Connection: close\r
Content-Length: 100\r
\r
you shall never see this message!
EOT
            close $sock;
        }
    },
);

done_testing;
