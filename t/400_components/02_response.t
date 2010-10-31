use strict;
use warnings;
use Test::More;
use Furl::Response;

my $res = Furl::Response->new(
    1, 200, 'OK',
    +{
        'x-foo'            => ['yay'],
        'x-bar'            => ['hoge'],
        'content-length'   => [9],
        'content-type'     => ['text/html'],
        'content-encoding' => ['chunked'],
    },
    'hit man'
);
is $res->protocol, 'HTTP/1.1';
is $res->code, 200;
is $res->message, 'OK';
isa_ok $res->headers, 'Furl::Headers';
is $res->content, 'hit man';
is($res->headers->header('X-Foo'), 'yay');
ok $res->is_success;
is $res->status_line, '200 OK';
is $res->content_length, 9;
is $res->content_type, 'text/html';
is $res->content_encoding, 'chunked';
my $hres = $res->as_http_response;
isa_ok $hres, 'HTTP::Response';
is $hres->code, 200;
is $hres->message, 'OK';
isa_ok $hres->headers, 'HTTP::Headers';
is $hres->content_type, 'text/html';
is $hres->content, 'hit man';
is $hres->protocol, 'HTTP/1.1';

done_testing;

