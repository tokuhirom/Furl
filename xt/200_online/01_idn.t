use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../..";
use t::Util;
use Test::More;
use Furl;
use Test::Requires qw(Plack::Request HTTP::Body), 'Net::IDN::Encode';

skip_if_offline();

my $url = 'http://日本語.jp/';

my $furl = Furl->new();
my $res  = $furl->get($url);
ok $res->is_success or $res->status_line;

utf8::decode($url);
$res = $furl->get($url);
ok $res->is_success or $res->status_line;

done_testing;
