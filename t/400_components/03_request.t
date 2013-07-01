use strict;
use warnings;
use Test::More;
use Test::Requires 'HTTP::Request';
use Furl::Request;

subtest 'normally' => sub {
    my $req = Furl::Request->new(
        'POST',
        'http://example.com/foo?q=bar',
        +{
            'x-foo'            => ['yay'],
            'x-bar'            => ['hoge'],
            'content-length'   => [7],
            'content-type'     => ['text/plain'],
        },
        'hit man'
    );
    $req->protocol('HTTP/1.0');

    is $req->method, 'POST';
    is $req->uri, 'http://example.com/foo?q=bar';
    isa_ok $req->headers, 'Furl::Headers';
    is($req->header('X-Foo'), 'yay');
    is $req->content, 'hit man';
    is $req->protocol, 'HTTP/1.0';
    is $req->request_line, 'POST /foo?q=bar HTTP/1.0';
    is $req->content_length, 7;
    is $req->content_type, 'text/plain';

    my $hreq = $req->as_http_request;

    isa_ok $hreq, 'HTTP::Request';
    is $hreq->method, 'POST';
    is $hreq->uri, 'http://example.com/foo?q=bar';
    isa_ok $hreq->headers, 'HTTP::Headers';
    is $hreq->content_type, 'text/plain';
    is $hreq->content, 'hit man';
    is $hreq->protocol, 'HTTP/1.0';
};

subtest 'parse' => sub {
    my $body = <<__REQ__;
POST /foo?q=bar HTTP/1.1
Host: example.com
X-Foo: yay
X-Bar: hoge
Content-Length: 7
Content-Type: text/plain

hit man
__REQ__
    chomp $body;

    my $req = Furl::Request->parse($body);

    is $req->method, 'POST';
    is $req->uri, 'http://example.com/foo?q=bar';
    isa_ok $req->headers, 'Furl::Headers';
    is($req->headers->header('X-Foo'), 'yay');
    is $req->content, 'hit man';
    is $req->protocol, 'HTTP/1.1';

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
};

subtest 'as_hashref' => sub {
    my $req = Furl::Request->new(
        'POST',
        'http://example.com/foo?q=bar',
        +{
            'x-foo'            => ['yay'],
            'x-bar'            => ['hoge'],
            'content-length'   => [7],
            'content-type'     => ['text/plain'],
        },
        'hit man'
    );
    $req->protocol('HTTP/1.1');

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

subtest 'as_string' => sub {
    subtest 'simple' => sub {
        my $req = Furl::Request->new(
            'POST',
            'http://example.com/foo?q=bar',
            +{
                'x-foo'            => ['yay'],
                'x-bar'            => ['hoge'],
                'content-length'   => [7],
                'content-type'     => ['text/plain'],
            },
            'hit man'
        );
        $req->protocol('HTTP/1.1');

        my $expected = join("\015\012",
            'POST http://example.com/foo?q=bar HTTP/1.1',
            'content-length: 7',
            'content-type: text/plain',
            'x-bar: hoge',
            'x-foo: yay',
            '',
            'hit man',
        );
        is($req->as_string, $expected);
    };
    subtest 'Furl#post' => sub {
        my $req = Furl::Request->new(
            'POST',
            'http://example.com/foo?q=bar',
            +{
                'x-foo'            => ['yay'],
                'x-bar'            => ['hoge'],
                'content-length'   => [7],
                'content-type'     => ['text/plain'],
            },
            [X => 'Y'],
        );
        # no protocol

        my $expected = join("\015\012",
            'POST http://example.com/foo?q=bar',
            'content-length: 7',
            'content-type: text/plain',
            'x-bar: hoge',
            'x-foo: yay',
            '',
            'X=Y',
        );
        is($req->as_string, $expected);
    };
};

done_testing;

