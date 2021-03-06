use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../..";
use t::Util;
use Test::More;
use Furl;

skip_if_offline();

my $url = 'http://www.google.co.jp/';

my $furl = Furl->new();
$furl->env_proxy();
for(1 .. 2) {
    note "getting";
    my $res = $furl->get($url);
    note "done";
    ok $res->is_success or diag $res->status_line
}
done_testing;
