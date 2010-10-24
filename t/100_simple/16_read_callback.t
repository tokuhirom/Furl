use strict;
use warnings;
use Furl;
use Test::TCP;
use Plack::Loader;
use Test::More;

use Plack::Request;
use Test::Requires 'IO::Callback';

my @data = qw/foo bar baz/;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new();
        my $fh =
          IO::Callback->new( '<',
            sub { my $x = shift @data; $x ? "-$x" : undef } );
        my ( $code, $msg, $headers, $content ) =
            $furl->put(
                "http://127.0.0.1:$port/",
                ['Content-Length' => length(join('', map { "-$_" } @data)) ],
                $fh,
            );
        is $code, 200, "request()";

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            my $req = Plack::Request->new($env);
            is $req->content, "-foo-bar-baz";
            return [ 200,
                [ 'Content-Length' => length($req->content) ],
                [$req->content]
            ];
        });
    }
);

