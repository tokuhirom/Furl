use strict;
use warnings;
use utf8;
use Test::More;
use Test::Requires qw(IO::Socket::SSL);
use Furl;
use t::Util;

skip_if_offline();

my $furl = Furl->new();
for my $url('https://mixi.jp/', 'https://mixi.jp') {
    my ($code, $msg, $headers, $content) = $furl->get($url);
    is $code, 200 or diag $content;
}

done_testing;
