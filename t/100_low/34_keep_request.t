use strict;
use warnings;
use Furl::HTTP;
use Furl::Request;
use Test::TCP;
use Test::More;
use t::HTTPServer;

test_tcp(
    client => sub {
        my $port = shift;

        subtest 'return request info' => sub {
            my $furl = Furl::HTTP->new(capture_request => 1);
            my @res = $furl->request( url => "http://127.0.0.1:$port/1", );

            my $content = pop @res;
            my $headers = pop @res;
            my $req = Furl::Request->parse($headers . $content);

            is $req->method, 'GET';
            is $req->uri, "http://127.0.0.1:$port/1";
        };
    },
    server => sub {
        my $port = shift;
        t::HTTPServer->new(port => $port)->run(sub {
            my $env = shift;
            return [ 200,
                [ 'Content-Length' => length('keep request') ],
                [ 'keep request' ]
            ];
        });
    }
);

done_testing;

