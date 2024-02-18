#!perl
use strict;
use warnings;
use Test::More;
use Furl;
use IO::Socket::SSL;
use t::Util;

skip_if_offline();

my $furl = Furl->new(
    ssl_opts => {
        SSL_verify_mode => SSL_VERIFY_PEER(),
    },
);
$furl->env_proxy();

my $res = $furl->get('https://foursquare.com/login');
ok $res->is_success, 'SSL get';
done_testing;

