use strict;
use warnings;

use Furl::HTTP;
use FindBin;
use lib "$FindBin::Bin/../..";
use t::HTTPServer;
use Test::TCP;
use Test::More;
use Test::Requires qw(Plack::Request HTTP::Body), 'Net::IDN::Encode';

sub test_uses_idn {
    my %specs = @_;
    my ($host, $expects, $desc) = @specs{qw/host expects desc/};

    subtest $desc => sub {
        test_tcp(
            client => sub {
                my $port = shift;
                my $furl = Furl::HTTP->new(timeout => 0.3);
                my $used = 0;
                no warnings 'redefine';
                local *Net::IDN::Encode::domain_to_ascii = sub {
                    $used = 1;
                    return '127.0.0.1',
                };
                my (undef, $code, $msg, $headers, $content) = $furl->request(
                    port       => $port,
                    path_query => '/',
                    host       => $host,
                );
                is $used, $expects, 'result';
            },
            server => sub {
                my $port = shift;
                t::HTTPServer->new(port => $port)->run(sub {
                    my $env = shift;
                    return [200, [], ['OK']];
                });
            },
        );
    };
}

test_uses_idn(
    host    => '127.0.0.1',
    expects => 0,
    desc    => 'local host',
);

test_uses_idn(
    host    => '例え.テスト',
    expects => 1,
    desc    => 'uses idn',
);

test_uses_idn(
    host    => '127.0.0._',
    expects => 0,
    desc    => 'in underscore',
);

done_testing;
