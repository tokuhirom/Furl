use strict;
use warnings;
use Furl;
use Test::Requires 'HTTP::Response';
use Test::TCP;
use Plack::Loader;
use Test::More;

use Plack::Request;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new();

        my $res = HTTP::Response->new(
            $furl->request(
                port       => $port,
                path_query => '/',
                host       => '127.0.0.1',
                headers    => [ "X-Foo" => "ppp", "Connection" => "Keep-Alive" ]
            )
        );

        is $res->code, 200;
        is $res->content_length, 2;
        is $res->content, 'OK';

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

