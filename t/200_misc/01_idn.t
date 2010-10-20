use strict;
use warnings;
use utf8;
use t::Util;
use Test::More;
use Furl;

plan skip_all => "TODO";

skip_if_offline();

my $url = 'http://例え.テスト/';

my $furl = Furl->new();
warn "connecting";
my ($code, $headers, $content) = $furl->get($url);

done_testing;
