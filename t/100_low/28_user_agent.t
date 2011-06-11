use strict;
use warnings;
use Furl::HTTP;
use IO::Socket::INET;
use Test::More;
use Test::TCP;
use t::HTTPServer;

test_tcp(
    client => sub {
        my $port = shift;
        my (undef, $code, undef, undef, $body) = Furl::HTTP->new(
            agent   => 'Foo',
            headers => ['X-Foo' => 'bar', 'X-Hoge' => 'fuga'],
        )->request(
            method  => 'GET',
            host    => '127.0.0.1',
            port    => $port,
            path    => '/',
            headers => ['User-Agent' => 'Bar'],
        );
        is $code, 200, 'code';
        is $body, '/', 'response body';
    },
    server => sub {
        my $port = shift;
        t::HTTPServer->new(port => $port)->run(sub {
            my $env = shift;
            is $env->{'HTTP_USER_AGENT'}, 'Bar', 'user-agent ok';
            is $env->{'HTTP_X_FOO'}, 'bar', 'x-foo ok';
            is $env->{'HTTP_X_HOGE'}, 'fuga', 'x-hoge ok';
            return [
                200,
                [ 'Content-Length', length $env->{REQUEST_URI} ],
                [ $env->{REQUEST_URI} ],
            ];
        });
    },
);

done_testing;
