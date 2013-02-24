use strict;
use warnings;
use Test::More;
use Test::Requires 'HTTP::Request';
use Furl::Request;

my $req = Furl::Request->new(
    1, 'POST', 'http://example.com/foo?q=bar',
    +{
        'x-foo'            => ['yay'],
        'x-bar'            => ['hoge'],
        'content-length'   => [7],
        'content-type'     => ['text/plain'],
    },
    'hit man'
);
is $req->protocol, 'HTTP/1.1';
is $req->method, 'POST';
is $req->uri, 'http://example.com/foo?q=bar';
isa_ok $req->headers, 'Furl::Headers';
is($req->headers->header('X-Foo'), 'yay');
is $req->content, 'hit man';
is $req->request_line, 'POST /foo?q=bar HTTP/1.1';
is $req->content_length, 7;
is $req->content_type, 'text/plain';

my $hreq = $req->as_http_request;
isa_ok $hreq, 'HTTP::Request';
is $hreq->method, 'POST';
is $hreq->uri, 'http://example.com/foo?q=bar';
isa_ok $hreq->headers, 'HTTP::Headers';
is $hreq->content_type, 'text/plain';
is $hreq->content, 'hit man';
is $hreq->protocol, 'HTTP/1.1';

subtest 'as_hashref' => sub {
    my $dat = $req->as_hashref;
    my $headers = delete $dat->{headers};
    is_deeply(
        $dat, {
            method => 'POST',
            uri => 'http://example.com/foo?q=bar',
            content => 'hit man',
            protocol => 'HTTP/1.1',
        }
    );
    is_deeply(
        [sort @{$headers}],
        [sort qw(
            content-type text/plain
            content-length 7
            x-foo yay
            x-bar hoge
        )]
    );
};

done_testing;

