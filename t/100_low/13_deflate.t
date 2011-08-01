use strict;
use warnings;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack::Middleware::Deflater', 'Compress::Raw::Zlib';
use Furl::HTTP;
use Test::TCP;
use Test::More;

use Plack::Request;
use File::Temp;

use t::Slowloris;

my $n = 10;
my $CONTENT = 'OK! YAY!' x 100;

for my $deflate (1, 0) {
    test_tcp(
        client => sub {
            my $port = shift;
            for my $encoding (qw/gzip deflate/) {
                my $furl = Furl::HTTP->new(
                    headers => ['Accept-Encoding' => $encoding],
                );
                for(1 .. $n) {
                    note "normal $_ $encoding";
                    my ( undef, $code, $msg, $headers, $content ) =
                        $furl->request(
                            url        => "http://127.0.0.1:$port/",
                        );
                    is $code, 200, "request()";
                    is Furl::HTTP::_header_get($headers, 'content-encoding'), $encoding;
                    is($content, $CONTENT) or do { require Devel::Peek; Devel::Peek::Dump($content) };
                }

                for(1 .. $n) {
                    note "to filehandle $_ $encoding";
                    open my $fh, '>', \my $content;
                    my ( undef, $code, $msg, $headers ) =
                        $furl->request(
                            url        => "http://127.0.0.1:$port/",
                            write_file => $fh,
                        );
                    is $code, 200, "request()";
                    is Furl::HTTP::_header_get($headers, 'content-encoding'), $encoding;
                    is($content, $CONTENT) or do { require Devel::Peek; Devel::Peek::Dump($content) };
                }

                for(1 .. $n){
                    note "to callback $_ $encoding";
                    my $content = '';
                    my ( undef, $code, $msg, $headers ) =
                        $furl->request(
                            url        => "http://127.0.0.1:$port/",
                            write_code => sub { $content .= $_[3] },
                        );
                    is $code, 200, "request()";
                    is Furl::HTTP::_header_get($headers, 'content-encoding'), $encoding;
                    is($content, $CONTENT) or do { require Devel::Peek; Devel::Peek::Dump($content) };
                }
            }
        },
        server => sub {
            my $port = shift;
            my $app;
            if ($deflate) {
                $app = Plack::Middleware::Deflater->wrap(sub {
                    my $env = shift;
                    like $env->{HTTP_USER_AGENT}, qr/\A Furl::HTTP/xms;
                    return [
                        200,
                        [ 'Content-Length' => length($CONTENT) ],
                        [$CONTENT],
                    ];
                });
            }
            else {
                $app = sub {
                    my $env = shift;
                    my $encoding = 'identity';
                    if ( defined $env->{HTTP_ACCEPT_ENCODING} ) {
                        for my $enc (qw(gzip deflate identity)) {
                            if ( $env->{HTTP_ACCEPT_ENCODING} =~ /\b$enc\b/ ) {
                                $encoding = $enc;
                                last;
                            }
                        }
                    }
                    like $env->{HTTP_USER_AGENT}, qr/\A Furl::HTTP/xms;
                    return [
                        200,
                        [
                            'Content-Length'   => length($CONTENT),
                            'Content-Encoding' => $encoding,
                        ],
                        [$CONTENT],
                    ];
                };
            }
            Slowloris::Server->new( port => $port )->run($app);
        },
    );
}

done_testing;
