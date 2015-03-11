use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;
use Plack::Request;
use Test::Requires qw(Plack::Request HTTP::Body), 'HTTP::Proxy';

plan tests => (10*2 + 8)*3;

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
        is $req->path, '/foo';
        is $req->header('X-Foo'), "ppp";
        like $req->header('User-Agent'), qr/\A Furl::HTTP /xms;
        my $content = "Hello, foo";
        return [ 200,
                 [ 'Content-Length' => length($content) ],
                 [ $content ]
             ];
    });
});

sub client (%) {
    my (%args) = @_;
    for (1..3) { # run some times for testing keep-alive.
        my $furl = Furl::HTTP->new(proxy => $args{proxy});
        my ( undef, $code, $msg, $headers, $content ) =
            $furl->request(
                url     => $args{request},
                headers => [ "X-Foo" => "ppp" ]
            );
        is $code, 200, "request()";
        is $msg, "OK";
        is Furl::HTTP::_header_get($headers, 'Content-Length'), 10;
        is Furl::HTTP::_header_get($headers, 'Via'), $args{via};
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
            via     => '1.0 VIA!VIA!VIA!',
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
            via     => '1.0 VIA!VIA!VIA!',
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

# SSL over proxy

test_tcp(
    client => sub {
        # emulate CONNECT for SSL proxying without a real SSL connection
        no warnings 'redefine';
        local *Furl::HTTP::connect_ssl_over_proxy = sub {
            my ($self, $proxy_host, $proxy_port, $host, $port, $timeout_at, $proxy_authorization) = @_;
            my $sock = $self->connect($proxy_host, $proxy_port, $timeout_at);
            my $p = "CONNECT $host:$port HTTP/1.0\015\012Server: $host\015\012";
            $p .= "\015\012";
            $self->write_all($sock, $p, $timeout_at) or fail;

            # read the entire response of CONNECT method
            my $buf = '';
            while ($buf !~ qr!(?:\015\012){2}!) {
                my $read = $self->read_timeout(
                    $sock, \$buf, $self->{bufsize}, length($buf), $timeout_at
                );
                defined $read or fail;
                $read != 0 or fail;
            }

            $sock;
        };

        my $proxy_port = shift;
        my $httpd_port = $httpd->port;
        client(
            proxy   => "http://127.0.0.1:$proxy_port",
            request => "https://127.0.0.1:$httpd_port/foo",
            # no via since the request goes directly to the origin server
        );
    },
    server => sub { # proxy server
        my $proxy_port = shift;
        my $proxy = Test::HTTP::Proxy->new(port => $proxy_port, via => $via);
        $proxy->start();
    },
);
