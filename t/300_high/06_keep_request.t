use strict;
use warnings;
use Furl;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;
use Data::Dumper;

use Plack::Request;
use Test::Requires qw(Plack::Request HTTP::Body), 'HTTP::Request';

test_tcp(
    client => sub {
        my $port = shift;

        my $furl = Furl->new(capture_request => 1);

        # request(GET)
        {
            my $res = $furl->request(url => "http://127.0.0.1:$port/foo", method => "GET");
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'GET';
        }

        # request(POST)
        {
            my $res = $furl->request(url => "http://127.0.0.1:$port/foo", method => "POST", content => 'GAH');
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'POST';
            is $req->content => 'GAH';
        }

        # ->get
        {
            my $res = $furl->get("http://127.0.0.1:$port/foo");
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'GET';
            is $req->content => '';
        }

        # ->get with headers
        {
            my $res = $furl->get("http://127.0.0.1:$port/foo", [
                'X-Furl-Requst' => 1,
            ]);
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'GET';
            is $req->content => '';
            is($req->headers->header('X-Furl-Requst'), 1) or diag Dumper($req->headers);
            is($req->header('X-Furl-Requst'), 1) or diag Dumper($req->headers);
            is join(',', $req->headers->keys), 'x-furl-requst';
        }

        # ->head
        {
            my $res = $furl->head("http://127.0.0.1:$port/foo");
            is $res->code, 200, "request()";
            is $res->body, '';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'HEAD';
            is $req->content => '';
        }

        # ->head with headers
        {
            my $res = $furl->head("http://127.0.0.1:$port/foo", [
                'X-Furl-Requst' => 1,
            ]);
            is $res->code, 200, "request()";
            is $res->body, '';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'HEAD';
            is $req->content => '';
            is $req->header('X-Furl-Requst'), 1;
        }

        # ->post
        {
            my $res = $furl->post("http://127.0.0.1:$port/foo", [], 'GAH');
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'POST';
            is $req->content => 'GAH';
        }

        # ->post with headers
        {
            my $res = $furl->post("http://127.0.0.1:$port/foo", [
                'X-Furl-Requst' => 1,
            ], 'GAH');
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'POST';
            is $req->content => 'GAH';
            is $req->header('X-Furl-Requst'), 1;
        }

        # ->put
        {
            my $res = $furl->put("http://127.0.0.1:$port/foo", [], 'GAH');
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'PUT';
            is $req->content => 'GAH';
        }

        # ->put with headers
        {
            my $res = $furl->put("http://127.0.0.1:$port/foo", [
                'X-Furl-Requst' => 1,
            ], 'GAH');
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'PUT';
            is $req->content => 'GAH';
            is $req->header('X-Furl-Requst'), 1;
        }

        # ->delete
        {
            my $res = $furl->delete("http://127.0.0.1:$port/foo");
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'DELETE';
            is $req->content => '';
        }

        # ->delete with headers
        {
            my $res = $furl->delete("http://127.0.0.1:$port/foo", [
                'X-Furl-Requst' => 1,
            ]);
            is $res->code, 200, "request()";
            is $res->body, 'OK';
            can_ok $res => 'request';

            my $req = $res->request;
            isa_ok $req => 'Furl::Request';
            is $req->uri => "http://127.0.0.1:$port/foo";
            is $req->method => 'DELETE';
            is $req->content => '';
            is $req->header('X-Furl-Requst'), 1;
        }

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            my $req = Plack::Request->new($env);
            return [ 200,
                [ 'Content-Length' => 2 ],
                [ 'OK' ]
            ];
        });
    }
);

