use strict;
use warnings;
use utf8;
use t::Util;
use Test::More;
use Furl;

# skip_if_offline(); # TODO: enable this

my $url = 'https://mixi.jp/';

my $furl = Furl->new();
my ($code, $msg, $headers, $content) = $furl->get($url);
is $code, 200;
diag $content if $code ne 200;

done_testing;
