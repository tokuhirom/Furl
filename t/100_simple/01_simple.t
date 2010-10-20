use strict;
use warnings;
use Furl;
use Test::TCP;
use Plack::Loader;
use Test::More;
use Plack::Util;
use Plack::Request;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new();
        for (1..3) {
            my ( $code, $headers, $content ) =
            $furl->request(
                port => $port,
                path => '/',
                host => '127.0.0.1',
                headers => [ "X-Foo" => "ppp" ]
            );
            is $code, 200;
            is Plack::Util::header_get($headers, 'Content-Length'), 2;
            is $content, 'OK';
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            my $req = Plack::Request->new($env);
            is $req->header('X-Foo'), "ppp";
            return [ 200, [ 'Content-Length' => 2 ], ['OK'] ];
        });
    }
);

