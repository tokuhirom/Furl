use strict;
use warnings;

BEGIN {
    my $target = {
        'Net/IDN/Encode.pm'    => 1,
        'IO/Socket/SSL.pm'     => 1,
        'Compress/Raw/Zlib.pm' => 1,
        'URI.pm'               => 1,
    };
    *CORE::GLOBAL::require = sub {
        return CORE::require($_[0]) unless $target->{$_[0]};
        die "Can't locate";
    };
}

use Furl::HTTP;
use Test::More;
use Test::TCP;
use t::HTTPServer;

sub mk_content {
    my ($feature, $library) = @_;
    my $msg = quotemeta
        "Internal Response: "
      . "$feature requires $library, but it is not available."
      . " Please install $library using your prefer CPAN client";
    return qr/$msg/;
}

subtest 'Net::IDN::Encode' => sub {
    my $furl = Furl::HTTP->new;
    my (undef, $code, $content) = $furl->get('http://()/');
    is $code, 500, 'code';
    like $content, mk_content(
        'Internationalized Domain Name (IDN)',
        'Net::IDN::Encode',
    ), 'content';
    ok !$furl->{errstr}, 'errstr';
};

subtest 'IO::Socket::SSL' => sub {
    my $furl = Furl::HTTP->new();
    my (undef, $code, $content) = $furl->get('https://foo.bar.baz/');
    is $code, 500, 'code';
    like $content, mk_content('SSL', 'IO::Socket::SSL'), 'content';
    ok !$furl->{errstr}, 'errstr';
};

subtest 'IO::Socket::SSL over proxy' => sub {
    my $furl = Furl::HTTP->new(proxy => 'https://foo.bar.baz/');
    my (undef, $code, $content) = $furl->get('https://foo.bar.baz/');
    is $code, 500, 'code';
    like $content, mk_content('SSL', 'IO::Socket::SSL'), 'content';
    ok !$furl->{errstr}, 'errstr';
};

subtest 'Compress::Raw::Zlib' => sub {
    test_tcp(
        client => sub {
            my $port = shift;
            my $furl = Furl::HTTP->new;
            my (undef, $code, $content) = $furl->get("http://127.0.0.1:$port/");
            is $code, 500, 'code';
            like $content, mk_content(
                'Content-Encoding', 'Compress::Raw::Zlib',
            ), 'content';
            ok !$furl->{errstr}, 'errstr';
        },
        server => sub {
            my $port = shift;
            t::HTTPServer->new(port => $port)->run(sub {
                my $env = shift;
                return [
                    200,
                    ['Content-Length' => 2, 'Content-Encoding' => 'gzip'],
                    ['OK'],
                ];
            });
        },
    );
};

subtest 'URI on redirect' => sub {
    test_tcp(
        client => sub {
            my $port = shift;
            my $furl = Furl::HTTP->new(max_redirects => 1);
            my (undef, $code, $content) = $furl->get("http://127.0.0.1:$port/");
            is $code, 500, 'code';
            like $content, mk_content(
                'redirect with relative url', 'URI',
            ), 'content';
            ok !$furl->{errstr}, 'errstr';
        },
        server => sub {
            my $port = shift;
            t::HTTPServer->new(port => $port)->run(sub {
                my $env = shift;
                return [
                    302,
                    [Location => '/foo'],
                    [],
                ];
            });
        },
    );
};

done_testing;
