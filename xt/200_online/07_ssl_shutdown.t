#!perl
use strict;
use warnings;
use Test::More;
use Furl;
use IO::Socket::SSL;

my $res = Furl->new()->get('https://foursquare.com/login');
ok $res->is_success, 'SSL get';
done_testing;

