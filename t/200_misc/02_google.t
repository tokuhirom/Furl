use strict;
use warnings;
use utf8;
use t::Util;
use Test::More;
use Furl;

plan skip_all => "TODO";

# skip_if_offline();

my $url = 'http://www.google.co.jp/';

my $furl = Furl->new();
note "getting";
my ($code, $headers, $content) = $furl->get($url);
note "done";
is($code, 200);

done_testing;
