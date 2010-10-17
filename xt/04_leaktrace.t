#!perl -w
use strict;
use Test::Requires qw(Test::LeakTrace);
use Test::More;

use Furl;

no_leaks_ok {
    my $furl = Furl->new();
    my($code, $headers, $body) = $furl->request(
        method => 'GET',
        host   => 'example.com',
        path   => '/',
    );
    $code == 200 or die $body;
};

my $furl = Furl->new();
no_leaks_ok {
    for(1 .. 10) {
        my($code, $headers, $body) = $furl->request(
            method => 'GET',
            host   => 'example.com',
            path   => '/',
        );
        $code == 200 or die $body;
    }
};

done_testing;

