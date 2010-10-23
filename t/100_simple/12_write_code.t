use strict;
use warnings;
use Furl;
use Test::TCP;
use Plack::Loader;
use Test::More;

use Plack::Request;
use File::Temp;
use Fcntl qw/:seek/;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new();
        my $content;
        my ( $code, $msg, $headers,  ) =
            $furl->request(
                port       => $port,
                path_query => '/foo',
                host       => '127.0.0.1',
                write_code => sub { $content .= $_[3] },
            );
        is $code, 200, "request()";
        is $content, "OK!YAY!";

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            my $content = "OK!YAY!";
            return [ 200,
                [ 'Content-Length' => length($content) ],
                [$content]
            ];
        });
    }
);

