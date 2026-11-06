use strict;
use warnings;
use Test::Requires 'Compress::Raw::Zlib';
use Furl;
use Furl::HTTP;
use IO::Socket::INET;
use Test::TCP;
use Test::More;

# A small gzip/deflate response must not inflate without bound in memory.
# Once the decoded body passes max_decompressed_size, Furl stops reading and
# returns an internal 500 response.

use Compress::Raw::Zlib qw(WANT_GZIP MAX_WBITS Z_OK Z_FINISH);

my $MiB = 1024 * 1024;

sub compress_zeros {
    my ($bytes, $window_bits) = @_;
    my ($d, $status) = Compress::Raw::Zlib::Deflate->new(
        -WindowBits => $window_bits, -Level => 9);
    $status == Z_OK or die "deflate init: $status";
    my $block = "\0" x $MiB;
    my $out = '';
    while ($bytes > 0) {
        my $in = $bytes >= $MiB ? $block : "\0" x $bytes;
        $bytes -= length $in;
        $d->deflate($in, my $o);
        $out .= $o;
    }
    $d->flush(my $o, Z_FINISH);
    return $out . $o;
}

my %body = (
    '/small' => do {
        my ($d) = Compress::Raw::Zlib::Deflate->new(-WindowBits => WANT_GZIP);
        $d->deflate('hello', my $o);
        $d->flush(my $t, Z_FINISH);
        $o . $t;
    },
    '/big'         => compress_zeros(2 * $MiB, WANT_GZIP),
    '/big-deflate' => compress_zeros(2 * $MiB, MAX_WBITS),
    '/big-stream'  => compress_zeros(101 * $MiB, WANT_GZIP),
);
# Inflating 100 MiB in memory is too heavy for every smoker.
$body{'/over-default'} = $body{'/big-stream'} if $ENV{AUTHOR_TESTING};
# Text that compresses to many KB, so it is inflated in many pieces.
my $TEXT = join '', map { "line $_ of the response body\n" } 1 .. 30000;
$body{'/text'} = do {
    my ($d) = Compress::Raw::Zlib::Deflate->new(-WindowBits => WANT_GZIP);
    $d->deflate($TEXT, my $o);
    $d->flush(my $t, Z_FINISH);
    $o . $t;
};
$body{'/text-chunked'} = $body{'/text'};
$body{'/big-chunked'} = $body{'/big'};

test_tcp(
    client => sub {
        my $port = shift;
        my $base = "http://127.0.0.1:$port";

        my $furl = Furl::HTTP->new(max_decompressed_size => $MiB);

        my (undef, $code, undef, undef, $content)
            = $furl->request(url => "$base/small");
        is $code, 200, 'small gzip response under the limit';
        is $content, 'hello', '... decoded';

        for my $path (qw(/text /text-chunked)) {
            (undef, $code, undef, undef, $content)
                = $furl->request(url => "$base$path");
            is $code, 200, "$path: larger body under the limit";
            ok $content eq $TEXT, '... decoded intact';
        }

        for my $path (qw(/big /big-deflate /big-chunked)) {
            my (undef, $code, $msg, $headers, $content)
                = $furl->request(url => "$base$path");
            is $code, 500, "$path: 2 MiB decoded body over a 1 MiB limit is a 500";
            like $msg, qr/max_decompressed_size/, '... with the limit error';
            is {@$headers}->{'X-Internal-Response'}, 1, '... as an internal response';
        }

        my $streamed = 0;
        (undef, $code, my $msg) = $furl->request(
            url        => "$base/big",
            write_code => sub { $streamed += length $_[3] },
        );
        is $code, 500, 'an explicit limit applies with write_code';
        like $msg, qr/max_decompressed_size/, '... with the limit error';
        cmp_ok $streamed, '<=', $MiB, '... and stops before the limit';

        # Other exceptions still propagate.
        my $ok = eval {
            $furl->request(
                url        => "$base/small",
                write_code => sub { die "callback died\n" },
            );
            1;
        };
        ok !$ok, 'an exception from write_code still propagates';
        is $@, "callback died\n", '... unchanged';

        (undef, $code, undef, undef, $content) = $furl->request(
            url                   => "$base/big",
            max_decompressed_size => 0,
        );
        is $code, 200, 'per-request max_decompressed_size => 0 disables the limit';
        is length($content), 2 * $MiB, '... full body decoded';

        my $res = Furl->new->get("$base/big");
        is $res->code, 200, 'default limit allows an ordinary 2 MiB body';
        is length($res->content), 2 * $MiB, '... full body decoded';

        # No default limit when streaming: the body does not grow in memory.
        $streamed = 0;
        $res = Furl->new->request(
            url        => "$base/big-stream",
            write_code => sub { $streamed += length $_[3] },
        );
        is $res->code, 200, 'default limit does not apply with write_code';
        is $streamed, 101 * $MiB, '... full body streamed';

        SKIP: {
            skip 'set AUTHOR_TESTING to inflate 100 MiB in memory', 2
                unless $ENV{AUTHOR_TESTING};
            $res = Furl->new->get("$base/over-default");
            is $res->code, 500, 'default limit (100 MiB) stops a 101 MiB decoded body';
            like $res->message, qr/max_decompressed_size/, '... with the limit error';
        }

        done_testing;
    },
    server => sub {
        my $port = shift;
        local $SIG{PIPE} = 'IGNORE';
        my $sock = IO::Socket::INET->new(
            LocalAddr => '127.0.0.1',
            LocalPort => $port,
            Listen    => 5,
            ReuseAddr => 1,
        ) or die "listen: $!";
        while (my $c = $sock->accept) {
            my $req = <$c>;
            next unless defined $req; # Test::TCP probing the port
            while (defined(my $line = <$c>)) { last if $line eq "\015\012" }
            my ($path) = $req =~ m{^\S+ (\S+)};
            my $payload = $body{$path};
            my $encoding = $path eq '/big-deflate' ? 'deflate' : 'gzip';
            if ($path =~ /-chunked\z/) {
                print {$c} "HTTP/1.1 200 OK\015\012",
                    "Content-Encoding: $encoding\015\012",
                    "Transfer-Encoding: chunked\015\012",
                    "Connection: close\015\012\015\012",
                    sprintf("%x\015\012", length $payload), $payload,
                    "\015\012", "0\015\012\015\012";
            }
            else {
                print {$c} "HTTP/1.1 200 OK\015\012",
                    "Content-Encoding: $encoding\015\012",
                    "Content-Length: ", length($payload), "\015\012",
                    "Connection: close\015\012\015\012", $payload;
            }
            close $c;
        }
    },
);
