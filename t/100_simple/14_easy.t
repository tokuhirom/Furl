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

my @data = (
    ['get', [], sub { is $_->method, 'GET'; }],
    ['get', [['X-Foo' => 'bar']], sub { is $_->method, 'GET'; is $_->header('X-Foo'), 'bar'; }],
    ['post', [[], 'doya'], sub { is $_->method, 'POST'; is $_->content_length, 4; is $_->content, 'doya' }],
    ['post', [[], ['do' => 'ya']], sub { is $_->method, 'POST'; is $_->content_length, 5; is $_->content, 'do=ya' }],
    ['head', [], sub { is $_->method, 'HEAD' }],
    ['head', [['X-Foo' => 'bar']], sub { is $_->method, 'HEAD'; is $_->header('X-Foo'), 'bar'; }],
    ['delete', [], sub { is $_->method, 'DELETE' }],
    ['delete', [['X-Foo' => 'bar']], sub { is $_->method, 'DELETE'; is $_->header('X-Foo'), 'bar'; }],
);

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new();
        my $url = "http://127.0.0.1:$port";

        my @d = @data;
        while (my $row = shift @d) {
            my ($method, $args, $code) = @$row;
            note "-- $method";
            my ($status, $msg, $headers, $body) = $furl->$method($url, @$args);
            $status == 200 or die "BAD: $status, $msg, $body";
        }

        done_testing;
    },
    server => sub {
        my $port = shift;
        my @d = @data;
        Plack::Loader->auto( port => $port )->run(sub {
            while (my $row = shift @d) {
                my $env     = shift;
                my $row = shift @data;
                my ($method, $args, $code) = @$row;
                local $_ = Plack::Request->new($env);
                $code->();
                return [
                    200,
                    [ 'Content-Length' => 2 ],
                    ['OK']
                ];
            }
        });
    }
);
