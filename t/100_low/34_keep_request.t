use strict;
use warnings;
use Furl::HTTP;
use Furl::Request;
use Test::TCP;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../..";
use t::HTTPServer;

test_tcp(
    client => sub {
        my $port = shift;

        subtest 'return request info' => sub {
            my $furl = Furl::HTTP->new(capture_request => 1);
            my @res = $furl->request( url => "http://127.0.0.1:$port/1", );

            my (
                $res_minor_version,
                $res_status,
                $res_msg,
                $res_headers,
                $res_content,
                $captured_req_headers,
                $captured_req_content,
                $captured_res_headers,
                $captured_res_content,
                $request_info,
            ) = @res;
            my $req = Furl::Request->parse($captured_req_headers . $captured_req_content);

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

