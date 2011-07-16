use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;

use Plack::Request;
use File::Temp;
use Fcntl qw/:seek/;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new();
        my $tmp = File::Temp->new(UNLINK => 1);
        my ( undef, $code, $msg, $headers,  ) =
            $furl->request(
                port       => $port,
                path_query => '/foo',
                host       => '127.0.0.1',
                write_file => $tmp,
            );
        is $code, 200, "request()";

        seek $tmp, 0, SEEK_SET;
        my $content = do { local $/; <$tmp> };
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

