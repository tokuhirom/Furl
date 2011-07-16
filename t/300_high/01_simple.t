use strict;
use warnings;
use Furl;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;

use Plack::Request;
use File::Temp;
use Fcntl qw/:seek/;

my @data = (
    ['get', [], sub {  }],
    ['get', [['X-Foo' => 'bar']], sub { is $_->header('X-Foo'), 'bar'; }],

    ['head', [], sub {  }],
    ['head', [['X-Foo' => 'bar']], sub { is $_->header('X-Foo'), 'bar'; }],

    ['post', [[], 'doya'],         sub { is $_->content_length, 4; is $_->content, 'doya' }],
    ['post', [undef, 'doya'],      sub { is $_->content_length, 4; is $_->content, 'doya' }],
    ['post', [[], ['do' => 'ya']], sub { is $_->content_length, 5; is $_->content, 'do=ya' }],
    ['post', [[], {'do' => 'ya'}], sub { is $_->content_length, 5; is $_->content, 'do=ya' }],
    ['post', [[], ['do' => 'ya', '=foo=' => 'bar baz']],
        sub {
            my $c = 'do=ya&%3Dfoo%3D=bar%20baz';
            is $_->content_length, length($c);
            is $_->content, $c;
        },
    ],

    ['put', [[], 'doya'],         sub { is $_->content_length, 4; is $_->content, 'doya' }],
    ['put', [undef, 'doya'],      sub { is $_->content_length, 4; is $_->content, 'doya' }],
    ['put', [[], ['do' => 'ya']], sub { is $_->content_length, 5; is $_->content, 'do=ya' }],
    ['put', [[], {'do' => 'ya'}], sub { is $_->content_length, 5; is $_->content, 'do=ya' }],
    ['put', [[], ['do' => 'ya', '=foo=' => 'bar baz']],
        sub {
            my $c = 'do=ya&%3Dfoo%3D=bar%20baz';
            is $_->content_length, length($c);
            is $_->content, $c;
        },
    ],

    ['delete', [], sub {  }],
    ['delete', [['X-Foo' => 'bar']], sub { is $_->header('X-Foo'), 'bar'; }],
);

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new();
        my $url = "http://127.0.0.1:$port";

        my @d = @data;
        while (my $row = shift @d) {
            my ($method, $args) = @$row;
            note "-- $method";
            my $res = $furl->$method($url, @$args);
            is $res->status, 200, "client: status by $method()"
                or die "BAD: " . join(', ', $res->status, $res->message, $res->content);
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
                is uc($_->method), uc($method), 'server: method';
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
