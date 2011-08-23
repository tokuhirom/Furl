use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;

use Plack::Request;
use Test::Requires qw(Plack::Request HTTP::Body), 'IO::Callback';

my @data = qw/foo bar baz/;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new();
        my $fh =
          IO::Callback->new( '<',
            sub { my $x = shift @data; $x ? "-$x" : undef } );
        my ( undef, $code, $msg, $headers, $content ) =
            $furl->request(
                method  => 'PUT',
                url     => "http://127.0.0.1:$port/",
                headers => ['Content-Length' => length(join('', map { "-$_" } @data)) ],
                content => $fh,
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

