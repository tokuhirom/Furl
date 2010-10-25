use strict;
use warnings;
use Test::More;
use Furl;

my @headers;
my ($minor_version, $status, $msg, $ret) = Furl::parse_http_response(
    join( '',
        "HTTP/1.0 200 OK\015\012",
        "X-Foo: Bar\015\012",
        " Baz\015\012",
        "\015\012" ), 0, \@headers, {});
is $minor_version, 0;
is $status, '200';
is $msg, 'OK';
is scalar(@headers), 2;
like $headers[1], qr{^Bar( Baz)?}; # TODO: "Bar Baz" is more better.
cmp_ok $ret,'>',0;

done_testing;

