use strict;
use warnings;
use utf8;
use t::Util;
use Test::More;
use Furl;

skip_if_offline();

my $url = 'http://www.yahoo.com/';

my $furl = Furl->new();
$furl->env_proxy();
for(1 .. 2) {
    note "getting";
    my $res = $furl->get($url);
    note "done";
    ok $res->is_success or $res->status_line;
}

done_testing;
