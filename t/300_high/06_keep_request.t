use strict;
use warnings;
use Furl;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;

use Plack::Request;
use Test::Requires qw(Plack::Request HTTP::Body), 'HTTP::Request';

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new(keep_request => 1);
        my $res = $furl->request(url => "http://127.0.0.1:$port/foo", method => "GET");
        is $res->code, 200, "request()";
        can_ok $res => 'request';

        my $req = $res->request;
        isa_ok $req => 'Furl::Request';
        is $req->uri => "http://127.0.0.1:$port/foo";
        is $req->method => 'GET';

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            my $req = Plack::Request->new($env);
            return [ 200,
                [ 'Content-Length' => 2 ],
                [ 'OK' ]
            ];
        });
    }
);

