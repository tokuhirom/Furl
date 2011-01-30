use strict;
use warnings;
use utf8;
use Test::More;
use Test::Requires qw(IO::Socket::SSL);
use Furl;
use t::Util;

skip_if_offline();

my $furl = Furl->new();
$furl->env_proxy();
for my $url('https://mixi.jp/', 'https://mixi.jp') {
    my $res = $furl->get($url);
    ok $res->is_success or diag $res->status_line;
}

done_testing;
