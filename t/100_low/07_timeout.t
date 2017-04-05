use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use Time::HiRes qw(time);

use Test::Requires qw(Plack::Util Plack::Request HTTP::Body), 'Plack::Request', 'Plack::Loader';

use FindBin;
use lib "$FindBin::Bin/../..";
use t::Slowloris;

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
        my $CONTENT_SIZE_MB_MAX = 256;
        WRITE_TIMEOUT_TEST: for (1 .. $n) {
            my $content_size_mb = 1;
            my ($elapsed, $code, $msg, $headers, $content);
            while(1) {
                note "Try sending $content_size_mb MiB content.";
                my $start_at = time;
                ( undef, $code, $msg, $headers, $content ) =
                    $furl->request(
                        host       => '127.0.0.1',
                        port       => $port,
                        method     => 'POST',
                        path_query => '/foo',
                        content    => do {
                            # should be larger than SO_SNDBUF + SO_RCVBUF + TCP_window_size
                            my $content = "0123456789abcdef" x 64 x 1024 x $content_size_mb;
                            open my $fh, '<', \$content or die "oops";
                            $fh;
                        },
                    );
                $elapsed = time - $start_at;
                if($msg !~ qr/Internal Response: Cannot read response header: timeout/) {
                    ## It's not read timeout. It seems OK.
                    last;
                }
                if($content_size_mb >= $CONTENT_SIZE_MB_MAX) {
                    fail "send $content_size_mb MiB but still write timeout did not occur.";
                    next WRITE_TIMEOUT_TEST;
                }
                note "Read timeout. Retry with more POST content";
                $content_size_mb *= 2;
            }
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
