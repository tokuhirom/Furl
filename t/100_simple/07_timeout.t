use strict;
use warnings;
use Furl;
use Test::TCP;
use Test::More;

use Plack::Request;
use Errno ();
my $n = shift(@ARGV) || 3;

use t::Slowloris;
$Slowloris::SleepByWrite = 5;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new(timeout => 1);
        for (1..$n) {
            my ( $code, $msg, $headers, $content ) =
                $furl->request(
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                    headers    => [ "X-Foo" => "ppp" ]
                );
            is $code, 500, "request()/$_";
            is $msg, "Internal Server Error";
            is ref($headers), "ARRAY";
            ok $content, 'content: ' . $content;
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        Slowloris::Server->new(port => $port)->run(sub {
            my $env = shift;
            #note explain $env;
            my $req = Plack::Request->new($env);
            is $req->header('X-Foo'), "ppp" if $env->{REQUEST_URI} eq '/foo';
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}) ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);

