use strict;
use warnings;
use Test::Requires 'Compress::Raw::Zlib';
use Furl;
use Furl::HTTP;
use IO::Socket::INET;
use Test::TCP;
use Test::More;

# A small gzip/deflate response must not inflate without bound in memory.
# Furl dies once the decoded body passes max_decompressed_size.

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
    '/over-default' => compress_zeros(101 * $MiB, WANT_GZIP),
);
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
            my $ok = eval { $furl->request(url => "$base$path"); 1 };
            ok !$ok, "$path: 2 MiB decoded body over a 1 MiB limit dies";
            like $@, qr/max_decompressed_size/, '... with the limit error';
        }

        my $streamed = 0;
        my $ok = eval {
            $furl->request(
                url        => "$base/big",
                write_code => sub { $streamed += length $_[3] },
            );
            1;
        };
        ok !$ok, 'limit applies with write_code';
        cmp_ok $streamed, '<=', $MiB, '... and stops before the limit';

        (undef, $code, undef, undef, $content) = $furl->request(
            url                   => "$base/big",
            max_decompressed_size => 0,
        );
        is $code, 200, 'per-request max_decompressed_size => 0 disables the limit';
        is length($content), 2 * $MiB, '... full body decoded';

        my $res = Furl->new->get("$base/big");
        is $res->code, 200, 'default limit allows an ordinary 2 MiB body';
        is length($res->content), 2 * $MiB, '... full body decoded';

        $ok = eval { Furl->new->get("$base/over-default"); 1 };
        ok !$ok, 'default limit (100 MiB) stops a 101 MiB decoded body';
        like $@, qr/max_decompressed_size/, '... with the limit error';

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
