use strict;
use warnings;
use utf8;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../..";
use t::HTTPServer;

# Scenario: The server returns bad content-length.
# RFC 2616 says Content-Length header's format is:
#
#    Content-Length    = "Content-Length" ":" 1*DIGIT
#
# But some server returns invalid format.
# It makes mysterious error message by Perl interpreter.
#
# Then, Furl validates content-length header before processing.
#
# ref. https://www.ietf.org/rfc/rfc2616.txt

my $n = shift(@ARGV) || 3;
test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(bufsize => 10, timeout => 3);
        my ( undef, $code, $msg, $headers, $content ) =
            $furl->request(
                port       => $port,
                path_query => '/foo',
                host       => '127.0.0.1',
                headers    => [ "X-Foo" => "ppp" ]
            );
        is $code, 500, "request()/$_";
        like $msg, qr/Internal Response/;
        like $content, qr/Bad Content-Length: 5963,5963/
            or do{ require Devel::Peek; Devel::Peek::Dump($content) };

        done_testing;
    },
    server => sub {
        my $port = shift;
        t::HTTPServer->new(port => $port)->run(sub {;
            my $env = shift;
            return [ 200,
                [ 'Content-Length' => '5963,5963' ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);
