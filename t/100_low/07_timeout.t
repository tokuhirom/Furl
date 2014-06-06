use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use Time::HiRes qw(time);

use Test::Requires qw(Plack::Util Plack::Request HTTP::Body), 'Plack::Request', 'Plack::Loader';

use t::Slowloris;

sub inspect_so_sndbuf {
    ## https://gist.github.com/kazuho/5624785
    require IO::Socket::INET;
    require Socket;
    require Net::EmptyPort;
    
    my $listen_sock = IO::Socket::INET->new(
        Listen => Net::EmptyPort::empty_port(),
        LocalPort => 0,
        LocalHost => '127.0.0.1',
        Proto => 'tcp',
        ReuseAddr => 1,
    ) or die $!;
    my $conn = IO::Socket::INET->new(
        PeerHost => '127.0.0.1',
        PeerPort => $listen_sock->sockport,
        Proto => 'tcp',
    ) or die $!;
    return $conn->sockopt(Socket::SO_SNDBUF());
}

sub content_for_write_timeout {
    my $so_sndbuf = eval { inspect_so_sndbuf() };
    if($so_sndbuf) {
        note("SO_SNDBUF = $so_sndbuf");
        my $len = $so_sndbuf * 2;
        note("Use content of $len Byte");
        return "A" x $len;
    }else {
        note("Failed to get SO_SNDBUF. Use 2MiB content.");
        return "0123456789abcdef" x 64 x 2048;
    }
}

my $n = shift(@ARGV) || 2;

$Slowloris::SleepBeforeRead  = 1;
$Slowloris::SleepBeforeWrite = 3;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(timeout => 1.5);

        note 'read_timeout';
        for (1 .. $n) {
            my $start_at = time;
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                );
            my $elapsed = time - $start_at;
            is $code, 500, "request()/$_";
            like $msg, qr/Internal Response: Cannot read response header: timeout/;
            is ref($headers), "ARRAY";
            ok $content, 'content: ' . $content;
            ok 1.3 <= $elapsed && $elapsed <= 2;
        }

        $furl = Furl::HTTP->new(timeout => 0.5);
        note 'write_timeout';
        for (1 .. $n) {
            my $start_at = time;
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    host       => '127.0.0.1',
                    port       => $port,
                    method     => 'POST',
                    path_query => '/foo',
                    content    => do {
                        # should be larger than SO_SNDBUF
                        my $content = content_for_write_timeout();
                        open my $fh, '<', \$content or die "oops";
                        $fh;
                    },
                );
            my $elapsed = time - $start_at;
            is $code, 500, "request()/$_";
            like $msg, qr/Internal Response: Failed to send content: timeout/;
            is ref($headers), "ARRAY";
            is Plack::Util::header_get($headers, 'X-Internal-Response'), 1;
            ok $content, 'content: ' . $content;
            ok 0.4 <= $elapsed && $elapsed <= 1;
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        Slowloris::Server->new(port => $port)->run(sub {
            my $env = shift;
            return [ 200, [], [$env->{REQUEST_URI}] ];
        });
    }
);

