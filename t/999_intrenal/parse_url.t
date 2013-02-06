use strict;
use warnings;
use Furl::HTTP;
use Test::More;

sub test_parse_url {
    my ($uri, $expects, $desc) = @_;
    local $@;
    my @parsed = eval { Furl::HTTP->_parse_url($uri) };
    unless ($@) {
        is_deeply \@parsed, $expects, $desc;
    }
    else {
        like $@, $expects;
    }
}

test_parse_url(
    'http://example.com/',
    [
        'http',
        undef,
        undef,
        'example.com',
        undef,
        '/',
    ],
    'root',
);

test_parse_url(
    'http://example.com',
    [
        'http',
        undef,
        undef,
        'example.com',
        undef,
        undef,
    ],
    'root (omit /)',
);

test_parse_url(
    'http://example.com/?foo=bar',
    [
        'http',
        undef,
        undef,
        'example.com',
        undef,
        '/?foo=bar',
    ],
    'root with query string'
);

test_parse_url(
    'http://example.com?foo=bar',
    [
        'http',
        undef,
        undef,
        'example.com',
        undef,
        '?foo=bar',
    ],
    'root with query string (omit /)'
);

test_parse_url(
    'http://example.com:5000/',
    [
        'http',
        undef,
        undef,
        'example.com',
        5000,
        '/',
    ],
    'with port',
);

test_parse_url(
    'http://example.com:5000',
    [
        'http',
        undef,
        undef,
        'example.com',
        5000,
        undef,
    ],
    'with port (omit /)',
);

test_parse_url(
    'http://example.com:5000/?foo=bar',
    [
        'http',
        undef,
        undef,
        'example.com',
        5000,
        '/?foo=bar',
    ],
    'with port and query string',
);

test_parse_url(
    'http://example.com:5000?foo=bar',
    [
        'http',
        undef,
        undef,
        'example.com',
        5000,
        '?foo=bar',
    ],
    'with port (omit /)',
);

test_parse_url(
    'http://example.com:5000/hoge/fuga?foo=bar',
    [
        'http',
        undef,
        undef,
        'example.com',
        5000,
        '/hoge/fuga?foo=bar',
    ],
    'popular url',
);

test_parse_url(
    'http://user:pass@example.com/',
    [
        'http',
        'user',
        'pass',
        'example.com',
        undef,
        '/',
    ],
    'auth url without port number',
);

test_parse_url(
    'http://user:pass@example.com:5000/hoge/fuga?foo=bar',
    [
        'http',
        'user',
        'pass',
        'example.com',
        5000,
        '/hoge/fuga?foo=bar',
    ],
    'auth & popular url',
);

test_parse_url(
    'http://example.com:5000foobar',
    qr/Passed malformed URL:/,
);

done_testing;
