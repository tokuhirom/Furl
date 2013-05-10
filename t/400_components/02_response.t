use strict;
use warnings;
use Test::More;
use Test::Requires qw(Plack::Request HTTP::Body), 'HTTP::Response';
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

subtest 'as_hashref' => sub {
    my $dat = $res->as_hashref;
    my $headers = delete $dat->{headers};
    is_deeply(
        $dat, {
            message => 'OK',
            code => 200,
            content => 'hit man',
            protocol => 'HTTP/1.1',
        }
    );
    is_deeply(
        [sort @{$headers}],
        [sort qw(
            content-type text/html
            x-foo yay
            x-bar hoge
            content-length 9
            content-encoding chunked
        )]
    );
};

subtest 'to_psgi' => sub {
    my $dat = $res->to_psgi;
    is(0+@$dat, 3);
    is($dat->[0], 200);
    is_deeply(
        [sort @{$dat->[1]}],
        [sort qw(
            content-type text/html
            x-foo yay
            x-bar hoge
            content-length 9
            content-encoding chunked
        )]
    );
    is_deeply($dat->[2], ['hit man']);
};

subtest decoded_content => sub {
    my $res = Furl::Response->new(
        1, 200, 'OK',
        +{
            'content-type' => ['text/plain; charset=UTF-8'],
        },
        "\343\201\202\343\201\204\343\201\206\343\201\210\343\201\212",
    );
    is $res->decoded_content, "\x{3042}\x{3044}\x{3046}\x{3048}\x{304a}";
};

subtest 'as_string' => sub {
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
    my $expected = join("\015\012",
        '200 OK',
        'content-encoding: chunked',
        'content-length: 9',
        'content-type: text/html',
        'x-bar: hoge',
        'x-foo: yay',
        '',
        'hit man',
    );
    is($res->as_string, $expected);
    is(length($res->as_string), length($expected));
};

done_testing;

