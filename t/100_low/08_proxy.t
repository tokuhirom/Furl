use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;
use Plack::Request;
use Test::Requires qw(Plack::Request HTTP::Body), 'HTTP::Proxy';

plan tests => 7*3;

my $verbose = 1;
{
    package Test::HTTP::Proxy;
    use parent qw(HTTP::Proxy);
    sub log {
        my($self, $level, $prefix, $msg) = @_;
        ::note "$prefix: $msg" if $verbose;
    }
}

my $via = "VIA!VIA!VIA!";

local $ENV{'HTTP_PROXY'} = '';
test_tcp(
    client => sub {
        my $proxy_port = shift;
        test_tcp(
            client => sub { # http client
                my $httpd_port = shift;
                for (1..3) { # run some times for testing keep-alive.
                    my $furl = Furl::HTTP->new(proxy => "http://127.0.0.1:$proxy_port");
                    my ( undef, $code, $msg, $headers, $content ) =
                        $furl->request(
                            url     => "http://127.0.0.1:$httpd_port/foo",
                            headers => [ "X-Foo" => "ppp" ]
                        );
                    is $code, 200, "request()";
                    is $msg, "OK";
                    is Furl::HTTP::_header_get($headers, 'Content-Length'), 10;
                    is Furl::HTTP::_header_get($headers, 'Via'), "1.0 $via";
                    is $content, 'Hello, foo'
                        or do{ require Devel::Peek; Devel::Peek::Dump($content) };
                }
            },
            server => sub { # http server
                my $httpd_port = shift;
                Plack::Loader->auto(port => $httpd_port)->run(sub {
                    my $env = shift;

                    my $req = Plack::Request->new($env);
                    is $req->header('X-Foo'), "ppp" if $env->{REQUEST_URI} eq '/foo';
                    like $req->header('User-Agent'), qr/\A Furl::HTTP /xms;
                    my $content = "Hello, foo";
                    return [ 200,
                        [ 'Content-Length' => length($content) ],
                        [ $content ]
                    ];
                });
            },
        );
    },
    server => sub { # proxy server
        my $proxy_port = shift;
        my $proxy = Test::HTTP::Proxy->new(port => $proxy_port, via => $via);
        $proxy->start();
    },
);
