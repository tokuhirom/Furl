use strict;
use warnings;

use Furl::HTTP;
use Test::More;
use Test::Requires qw(IO::Socket::SSL);
use Time::HiRes qw(time);

my $n = shift(@ARGV) || 2;

# TODO add proxy tests

note 'name resolution error';
{
    my $furl = Furl::HTTP->new(timeout => 60);
    my (undef, $code, $msg, $headers, $content) =
        $furl->request(
            host => 'a.', # an non-existent gTLD
            port => 80,
            path_query => '/foo',
        );
    is $code, 500, "nameerror/$_";
    like $msg, qr/Internal Response: Cannot resolve host name: a/;
    is ref($headers), 'ARRAY';
    ok $content, "content: $content";
}

note 'refused error';
{
    my $furl = Furl::HTTP->new(timeout => 60);
    for my $scheme (qw(http https)) {
        for (1 .. $n) {
            my $start_at = time;
            my (undef, $code, $msg, $headers, $content) =
                $furl->request(
                    host       => '255.255.255.255',
                    port       => 80,
                    scheme     => $scheme,
                    path_query => '/foo',
                );
            my $elapsed = time - $start_at;
            is $code, 500, "request/$scheme/$_";
            like $msg, qr/Internal Response: (Cannot connect to 255.255.255.255:80:|Cannot create SSL connection:)/;
            is ref($headers), 'ARRAY';
            ok $content, "content: $content";
            ok $elapsed < 0.5;
        }
    }
}

note 'timeout error';
# Timeout parameter of IO::Socket::SSL does not seem to be accurate, so only test http
for my $scheme (qw(http)) {
    for my $timeout (1.5, 4, 8) {
        my $furl = Furl::HTTP->new(timeout => $timeout);
        my $start_at = time;
        my (undef, $code, $msg, $headers, $content) =
            $furl->request(
                host       => 'google.com',
                port       => 81,
                scheme     => $scheme,
                path_query => '/foo',
            );
        my $elapsed = time - $start_at;
        is $code, 500, "request/$scheme/timeout/$timeout";
        like $msg, qr/Internal Response: Cannot connect to google.com:81:/;
        is ref($headers), 'ARRAY';
        ok $content, "content: $content";
        ok $timeout - 0.1 <= $elapsed && $elapsed <= $timeout + 1, "elapsed: $elapsed";
    }
}

done_testing;
