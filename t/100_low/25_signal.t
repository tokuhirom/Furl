use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use t::HTTPServer;

my $n = shift(@ARGV) || 3;
test_tcp(
    client => sub {
        my $port = shift;
        my $abort_on_eintr = 0;
        my $furl = Furl::HTTP->new(
            bufsize        => 10,
            abort_on_eintr => sub { $abort_on_eintr },
            timeout        => undef,
        );
        local $SIG{ALRM} = sub {};
        for (1 .. $n) {
            # ignore signal
            $abort_on_eintr = undef;
            alarm(2);
            my ($undef, $code, $msg, $headers, $content) =
                $furl->request(
                    port       => $port,
                    path_query => '/',
                    host       => '127.0.0.1',
                );
            is $code, 200, "ignore signal";
            alarm(0);
            sleep(4); # wait until the server stops handling the request
            # cancel on signal
            $abort_on_eintr = 1;
            alarm(2);
            ($undef, $code, $msg, $headers, $content) =
                $furl->request(
                    port       => $port,
                    path_query => '/5',
                    host       => '127.0.0.1',
                );
            is $code, 500, "cancelled";
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
