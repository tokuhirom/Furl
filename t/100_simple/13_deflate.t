use strict;
use warnings;
use Furl;
use Test::TCP;
use Plack::Loader;
use Test::More;
use Plack::Util;
use Plack::Request;
use File::Temp;
use Fcntl qw/:seek/;
use Test::Requires 'Plack::Middleware::Deflater';

TODO: {
    local $TODO = 'DEFLATE';

    test_tcp(
        client => sub {
            my $port = shift;
            my $furl = Furl->new();

            {
                my ( $code, $msg, $headers, $content ) =
                    $furl->request(
                        url        => "http://127.0.0.1:$port/",
                        headers    => ['Accept-Encoding' => 'gzip'],
                    );
                is $code, 200, "request()";
                is Plack::Util::header_get($headers, 'content-encoding'), "gzip";
                is($content, "OK!YAY!") or do { require Devel::Peek; Devel::Peek::Dump($content) };
            }

            {
                open my $fh, '>', \my $content;
                my ( $code, $msg, $headers ) =
                    $furl->request(
                        url        => "http://127.0.0.1:$port/",
                        headers    => ['Accept-Encoding' => 'gzip'],
                        write_file => $fh,
                    );
                is $code, 200, "request()";
                is Plack::Util::header_get($headers, 'content-encoding'), "gzip";
                is($content, "OK!YAY!") or do { require Devel::Peek; Devel::Peek::Dump($content) };
            }

            {
                my $content = '';
                my ( $code, $msg, $headers ) =
                    $furl->request(
                        url        => "http://127.0.0.1:$port/",
                        headers    => ['Accept-Encoding' => 'gzip'],
                        write_code => sub { $content .= $_[3] },
                    );
                is $code, 200, "request()";
                is Plack::Util::header_get($headers, 'content-encoding'), "gzip";
                is($content, "OK!YAY!") or do { require Devel::Peek; Devel::Peek::Dump($content) };
            }

            done_testing;
        },
        server => sub {
            my $port = shift;
            Plack::Loader->auto( port => $port )->run(
                Plack::Middleware::Deflater->wrap(
                    sub {
                        my $env     = shift;
                        my $content = "OK!YAY!";
                        return [
                            200, [ 'Content-Length' => length($content) ],
                            [$content]
                        ];
                    }
                )
            );
        }
    );
};
