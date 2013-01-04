# to test "stop_if"
use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use t::HTTPServer;

plan skip_all => "Win32 is not supported" if Furl::HTTP::WIN32;

my $n = shift(@ARGV) || 3;
test_tcp(
    client => sub {
        my $port = shift;
        my $stop_if = 0;
        my $furl = Furl::HTTP->new(
            bufsize => 10,
            stop_if => sub { $stop_if },
        );
        local $SIG{ALRM} = sub {
            note "caught ALRM";
        };
        for (1 .. $n) {
            note "try it $_ with stop_if=false";
            # ignore signal
            $stop_if = undef;
            alarm(2);
            my ($undef, $code, $msg, $headers, $content) =
                $furl->request(
                    port       => $port,
                    path_query => '/',
                    host       => '127.0.0.1',
                );
            is $code, 200, "ignore signal ($_)";
            alarm(0);
            sleep(4); # wait until the server stops handling the request
            # cancel on signal
            note "try it $_ with stop_if=true";
            $stop_if = 1;
            alarm(2);
            ($undef, $code, $msg, $headers, $content) =
                $furl->request(
                    port       => $port,
                    path_query => '/5',
                    host       => '127.0.0.1',
                );
            is $code, 500, "cancelled ($_)";
            alarm(0);
            sleep(4); # wait until the server stops handling the request
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        t::HTTPServer->new(port => $port)->run(sub {
            my $env = shift;
            sleep(4);
            return [
                200,
                [
                    'Content-Type'   => 'text/plain',
                    'Content-Length' => 5,
                ],
                [ 'hello' ],
            ];
        });
    },
);
