use strict;
use warnings;
use Test::More;
use Furl::Headers;
use Test::Requires qw(Plack::Request HTTP::Body), 'HTTP::Headers';
use HTTP::Headers;

subtest 'total test' => sub {
    my $h = Furl::Headers->new([
        'x-foo' => 1,
        'x-bar' => 2,
        'x-foo' => 3,
    ]);
    is_deeply(
        +{%$h},
        +{ 'x-foo' => [qw/1 3/], 'x-bar' => [2] },
        'make from arrayref'
    );
    is( $h->header('X-Foo'), "1, 3" );
    is_deeply( [$h->header('X-Foo')], [qw/1 3/] );
    is( $h->header('X-Bar'), 2 );
    is( $h->header('X-Bar'), 2 );
    is_deeply( [$h->header('X-Foo')], [qw/1 3/] );
    $h->header('X-Poo', 'san');
    is( $h->header('X-Poo'), 'san' );
    $h->header('X-Poo', ['san', 'winnie']);
    is( $h->header('X-Poo'), 'san, winnie' );
    is_deeply( [$h->header('X-Poo')], ['san', 'winnie'] );
    is(join(',', sort $h->keys), 'x-bar,x-foo,x-poo');
    $h->remove_header('x-foo');
    is(join(',', sort $h->keys), 'x-bar,x-poo');
    is(join(',', sort $h->header_field_names), 'x-bar,x-poo', 'header_field_names');
    is_deeply([sort split /\015\012/, $h->as_string], [sort split /\015\012/, "x-bar: 2\015\012x-poo: san\015\012x-poo: winnie\015\012"], 'as_string');
    is(join(',', sort $h->flatten), '2,san,winnie,x-bar,x-poo,x-poo');

    my $hh = $h->as_http_headers;
    is $hh->header('x-bar'), '2';
    is $hh->header('x-poo'), 'san, winnie';
};

subtest 'from hashref' => sub {
    my $h = Furl::Headers->new({
        'x-foo' => [1, 3],
        'x-bar' => [2],
    });
    is( $h->header('X-Foo'), '1, 3', 'make from hashref' );
    is_deeply( [$h->header('X-Foo')], [qw/1 3/] );
    is( $h->header('X-Bar'), 2 );
    is_deeply( [$h->header('X-Bar')], [2] );
};

subtest 'shorthand' => sub {
    my $h = Furl::Headers->new(
        [
            'expires'           => '1111',
            'last-modified'     => '2222',
            'if-modified-since' => '3333',
            'content-type'      => 'text/html',
            'content-length'    => '4444',
        ]
    );
    is $h->expires,           '1111';
    is $h->last_modified,     '2222';
    is $h->if_modified_since, '3333';
    is $h->content_type,      'text/html';
    is $h->content_length,    4444;
};

subtest 'clone' => sub {
    my $h1 = Furl::Headers->new([
         expires => 1111,
    ]);
    my $h2 = $h1->clone();
    is $h2->expires, '1111';
    $h2->last_modified('2222');
    is $h2->last_modified, '2222';
    isnt $h1->last_modified, '2222';
};

# TODO make from hashref

done_testing;
