#!perl -w
use strict;
use Test::Requires qw(Plack::Request HTTP::Body), qw(Test::LeakTrace);
use Test::More;

use Furl;

no_leaks_ok {
    my $furl = Furl->new();
    my $res = $furl->request(
        method => 'GET',
        host   => 'example.com',
        path   => '/',
    );
    $res->is_success or die $res->status_line;
};

my $furl = Furl->new();
no_leaks_ok {
    for(1 .. 5) {
        my $res = $furl->request(
            method => 'GET',
            host   => 'example.com',
            path   => '/',
        );
        $res->is_success or die $res->status_line;
    }
};

done_testing;

