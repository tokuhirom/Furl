use strict;
use warnings;
use Furl::HTTP qw/HEADERS_NONE/;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;

use Plack::Request;
my $n = shift(@ARGV) || 3;
test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(
            bufsize       => 10,
            header_format => HEADERS_NONE,
        );
        for (1 .. $n) {
            my %special_headers = (
                'x-bar' => '',
            );
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                    headers    => [ "X-Foo" => "ppp" ],
                    special_headers => \%special_headers,
                );
            is $code, 200, "request()/$_";
            is $msg, "OK";
            is $special_headers{'content-length'}, 4, 'header'
                or diag(explain(\%special_headers));
            is $special_headers{'x-bar'}, 10;
            is $content, '/foo'
                or do{ require Devel::Peek; Devel::Peek::Dump($content) };
            is $headers, undef;
        }

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            #note explain $env;
            my $req = Plack::Request->new($env);
            is $req->header('X-Foo'), "ppp" if $env->{REQUEST_URI} eq '/foo';
            like $req->header('User-Agent'), qr/\A Furl::HTTP /xms;
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}), 'X-Bar' => 10 ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);

