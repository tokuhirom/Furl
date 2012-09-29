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
        my $furl = Furl->new();
        my $req = HTTP::Request->new(POST => "http://127.0.0.1:$port/foo", ['X-Foo' => 'ppp', 'Content-Length' => 3], 'yay');
        my $res = $furl->request( $req );
        is $res->code, 200, "request()";

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            #note explain $env;
            my $req = Plack::Request->new($env);
            is $req->header('X-Foo'), "ppp";
            is $req->header('Host'),  "127.0.0.1:$port";
            is $req->path_info,  "/foo";
            is $req->content,  "yay";
            is $req->content_length,  3;
            is $req->method,  "POST";
            return [ 200,
                [ 'Content-Length' => length($req->content) ],
                [$req->content]
            ];
        });
    }
);

