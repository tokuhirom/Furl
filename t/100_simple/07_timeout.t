use strict;
use warnings;
use Furl;
use Test::TCP;
use Test::More;
use t::Slowloris;

my $n = shift(@ARGV) || 2;

$Slowloris::SleepBeforeRead  = 1;
$Slowloris::SleepBeforeWrite = 3;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new(timeout => 1.5);

        note 'read_timeout';
        for (1 .. $n) {
            my ( $code, $msg, $headers, $content ) =
                $furl->request(
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                );
            is $code, 500, "request()/$_";
            is $msg, "Internal Server Error";
            is ref($headers), "ARRAY";
            ok $content, 'content: ' . $content;
        }

        $furl = Furl->new(timeout => 0.5);
        note 'write_timeout';
        for (1 .. $n) {
            my ( $code, $msg, $headers, $content ) =
                $furl->request(
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                );
            is $code, 500, "request()/$_";
            is $msg, "Internal Server Error";
            is ref($headers), "ARRAY";
            ok $content, 'content: ' . $content;
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        Slowloris::Server->new(port => $port)->run(sub {
            my $env = shift;
            return [ 200, [], [$env->{REQUEST_URI}] ];
        });
    }
);

