#!perl
use strict;
use warnings;
use Test::More;
use Furl;
use IO::Socket::SSL;

my $res = Furl->new(
    ssl_opts => {
        SSL_verify_mode => SSL_VERIFY_PEER(),
    },
)->get('https://foursquare.com/login');
ok $res->is_success, 'SSL get';
done_testing;

