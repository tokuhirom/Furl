use strict;
use warnings;
use utf8;
use Test::More;
use Furl::HTTP;
use Furl;

is($Furl::VERSION, $Furl::HTTP::VERSION);

done_testing;

