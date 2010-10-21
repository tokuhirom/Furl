use strict;
use warnings;
use utf8;
use Test::More;
use Test::Requires qw(IO::Socket::SSL);
use Furl;
use t::Util;

# skip_if_offline(); # TODO: enable this

my $furl = Furl->new();
for my $url('https://mixi.jp/', 'https://mixi.jp') {
    my ($code, $msg, $headers, $content) = $furl->get($url);
    is $code, 200;
    diag $content if $code ne 200;
}

done_testing;
