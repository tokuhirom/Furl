use strict;
use warnings;
use Test::More;
use Furl;

my ($minor_version, $status, $msg, $content_length, $connection, $location, $transfer_encoding, $content_encoding, $headers, $ret) = Furl::parse_http_response(
    join( '',
        "HTTP/1.0 200 OK\015\012",
        "Content-Length: 1234\015\012",
        "Connection: close\015\012",
        "Location: http://mixi.jp/\015\012",
        "Transfer-Encoding: chunked\015\012",
        "Content-Encoding: gzip\015\012",
        "X-Foo: bar\015\012",
        "\015\012" ), 0
  );
is $minor_version, 0;
is $status, '200';
is $msg, 'OK';
is $content_length, 1234;
is $connection, 'close';
is $location, 'http://mixi.jp/';
is $transfer_encoding, 'chunked';
is $content_encoding, 'gzip';
is_deeply $headers,
  [
    'Content-Length',    1234,
    'Connection',        'close',
    'Location',          'http://mixi.jp/',
    'Transfer-Encoding', 'chunked',
    'Content-Encoding',  'gzip',
    'X-Foo',             'bar'
  ];
cmp_ok $ret,'>',0;

done_testing;

