use strict;
use warnings;
use utf8;
use t::Util;
use Test::More;
use Furl;

plan skip_all => "alarm() does not work on $^O" if $^O eq 'MSWin32';

# skip_if_offline();

my $url = 'http://www.yahoo.com/';

alarm 10;
local $SIG{ALRM} = sub { die "TIMEOUT!"; };
my $furl = Furl->new();
note "getting";
my ($code, $msg, $headers, $content) = $furl->get($url);
note "done";
is($code, 200);

done_testing;
