use strict;
use warnings;
use Test::More;
use Furl;

my %res = (
    'content-length'    => undef,
    'connection'        => '',
    'location'          => '',
    'transfer-encoding' => '',
    'content-encoding'  => '',
);
my @headers;
my ($minor_version, $status, $msg, $ret) = Furl::parse_http_response(
    join( '',
        "HTTP/1.0 200 OK\015\012",
        "Content-Length: 1234\015\012",
        "Connection: close\015\012",
        "Location: http://mixi.jp/\015\012",
        "Transfer-Encoding: chunked\015\012",
        "Content-Encoding: gzip\015\012",
        "X-Foo: Bar\015\012",
        "\015\012" ), 0, \@headers, \%res);
is $minor_version, 0;
is $status, '200';
is $msg, 'OK';
is $res{'content-length'}, 1234;
is $res{'connection'}, 'close';
is $res{'location'}, 'http://mixi.jp/';
is $res{'transfer-encoding'}, 'chunked';
is $res{'content-encoding'}, 'gzip';
is_deeply \@headers,
  [
    'content-length',    1234,
    'connection',        'close',
    'location',          'http://mixi.jp/',
    'transfer-encoding', 'chunked',
    'content-encoding',  'gzip',
    'x-foo',             'Bar'
  ];
cmp_ok $ret,'>',0;

done_testing;

