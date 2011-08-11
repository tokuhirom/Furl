use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use t::HTTPServer;

my $server = sub {
    my $port = shift;
    t::HTTPServer->new(port => $port)->run(sub {
        my $env = shift;
        return [
            200,
            [ 'Content-Length' => length($env->{REQUEST_URI}) ],
            [ $env->{REQUEST_URI} ],
        ];
    });
};

note '/foo => /foo';
test_tcp(
    server => $server,
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(bufsize => 10, timeout => 3);

        do {
            my (undef, $code, $msg, $headers, $content) = $furl->request(
                port       => $port,
                path_query => '/foo',
                host       => '127.0.0.1',
            );
            is $code, 200, "code";
            is $msg, "OK" , "msg";
            is $content, "/foo", "return path query";
        };

        do {
            my $path_query = '/foo';
            my ( undef, $code, $msg, $headers, $content ) = $furl->request(
                url    => "http://127.0.0.1:$port$path_query",
                method => 'GET',
            );
            is $code, 200, 'code';
            is $msg, 'OK', 'msg';
            is $content, '/foo';
        };
    },
);

note 'foo => /foo';
test_tcp(
    server => $server,
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(bufsize => 10, timeout => 3);

        do {
            my (undef, $code, $msg, $headers, $content) = $furl->request(
                port       => $port,
                path_query => 'foo',
                host       => '127.0.0.1',
            );
            is $code, 200, 'code';
            is $msg, 'OK' , 'msg';
            is $content, '/foo', 'return path query';
        };
    },
);

note '/?foo=bar => /?foo=bar';
test_tcp(
    server => $server,
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(bufsize => 10, timeout => 3);

        do {
            my (undef, $code, $msg, $headers, $content) = $furl->request(
                port       => $port,
                path_query => '/?foo=bar',
                host       => '127.0.0.1',
            );
            is $code, 200, 'code';
            is $msg, 'OK' , 'msg';
            is $content, '/?foo=bar', 'return path query';
        };

        do {
            my $path_query = '/?foo=bar';
            my ( undef, $code, $msg, $headers, $content ) = $furl->request(
                url    => "http://127.0.0.1:$port$path_query",
                method => 'GET',
            );
            is $code, 200, 'code';
            is $msg, 'OK', 'msg';
            is $content, '/?foo=bar';
        };
    },
);

note '?foo=bar => /?foo=bar';
test_tcp(
    server => $server,
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(bufsize => 10, timeout => 3);

        do {
            my (undef, $code, $msg, $headers, $content) = $furl->request(
                port       => $port,
                path_query => '?foo=bar',
                host       => '127.0.0.1',
            );
            is $code, 200, "code";
            is $msg, "OK" , "msg";
            is $content, "/?foo=bar", "return path query";
        };

        do {
            my $path_query = '?foo=bar';
            my ( undef, $code, $msg, $headers, $content ) = $furl->request(
                url    => "http://127.0.0.1:$port$path_query",
                method => 'GET',
            );
            is $code, 200, 'code';
            is $msg, 'OK', 'msg';
            is $content, '/?foo=bar';
        };
    },
);

done_testing;
