use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;
use Plack::Request;
use Test::Requires qw(Plack::Request HTTP::Body), 'HTTP::Proxy';

plan tests => 9*3*2;

my $verbose = 1;
{
    package Test::HTTP::Proxy;
    use parent qw(HTTP::Proxy);
    sub log {
        my($self, $level, $prefix, $msg) = @_;
        ::note "$prefix: $msg" if $verbose;
    }
}

{
    package Test::UserAgent;
    use parent qw(LWP::UserAgent);
    use Test::More;

    sub real_httpd_port {
        my ($self, $port) = @_;
        $self->{httpd_port} = $port if defined $port;
        return $self->{httpd_port};
    }

    sub simple_request {
        my ($self, $req, @args) = @_;
        my $uri = $req->uri;
        my $host = $req->header('Host');

        if ($self->real_httpd_port) {
            # test for URL with a default port
            like $uri.q(), qr!^http://[^:]+/!,
                'No port number in the request line';
            unlike $host, qr!:!,
                'No port number in Host header';

            # replace the port number to correctly connect to the test server
            $uri->port($self->real_httpd_port);
        } else {
            # test for URL with non-default port

            like $uri.q(), qr!^http://[^/]+:[0-9]+/!,
                'A port number in the request line';
            like $host, qr/:[0-9]+$/,
                'A port number in Host header';
        }

        return $self->SUPER::simple_request($req, @args);
    }
}

my $via = "VIA!VIA!VIA!";

my $httpd = Test::TCP->new(code => sub {
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
});

sub client (%) {
    my (%url) = @_;
    for (1..3) { # run some times for testing keep-alive.
        my $furl = Furl::HTTP->new(proxy => $url{proxy});
        my ( undef, $code, $msg, $headers, $content ) =
            $furl->request(
                url     => $url{request},
                headers => [ "X-Foo" => "ppp" ]
            );
        is $code, 200, "request()";
        is $msg, "OK";
        is Furl::HTTP::_header_get($headers, 'Content-Length'), 10;
        is Furl::HTTP::_header_get($headers, 'Via'), "1.0 $via";
        is $content, 'Hello, foo'
            or do{ require Devel::Peek; Devel::Peek::Dump($content) };
    }
}

sub test_agent () {
    return Test::UserAgent->new(
        env_proxy  => 1,
        keep_alive => 2,
        parse_head => 0,
    );
}

local $ENV{'HTTP_PROXY'} = '';

# Request target with non-default port

test_tcp(
    client => sub {
        my $proxy_port = shift;
        my $httpd_port = $httpd->port;
        client(
            proxy   => "http://127.0.0.1:$proxy_port",
            request => "http://127.0.0.1:$httpd_port/foo",
        );
    },
    server => sub { # proxy server
        my $proxy_port = shift;
        my $proxy = Test::HTTP::Proxy->new(port => $proxy_port, via => $via);
        $proxy->agent(test_agent);
        $proxy->start();
    },
);

# Request target with default port

test_tcp(
    client => sub {
        my $proxy_port = shift;
        my $httpd_port = $httpd->port;
        client(
            proxy   => "http://127.0.0.1:$proxy_port",
            request => "http://127.0.0.1/foo", # default port
        );
    },
    server => sub { # proxy server
        my $proxy_port = shift;
        my $proxy = Test::HTTP::Proxy->new(port => $proxy_port, via => $via);
        $proxy->agent(test_agent);
        $proxy->agent->real_httpd_port($httpd->port);
        $proxy->start();
    },
);
