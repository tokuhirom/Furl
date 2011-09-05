use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use t::HTTPServer;

test_tcp(
    client => sub {
        my $port = shift;

        subtest 'set agent' => sub {
            my $furl = Furl::HTTP->new();
            $furl->agent('foobot');
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request( url => "http://127.0.0.1:$port/1", );
            is $code, 200;
            is $content, 'foobot';
        };

        subtest 'set agent at request' => sub {
            my $furl = Furl::HTTP->new();
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    url     => "http://127.0.0.1:$port/2",
                    headers => [ "User-Agent" => "foobot" ]
                );
            is $code, 200;
            like $content, qr/\A Furl::HTTP\/[^,]+,\sfoobot /xms;
        };

        subtest 'set agent and request with agent' => sub {
            my $furl = Furl::HTTP->new();
            $furl->agent('foobot');
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    url     => "http://127.0.0.1:$port/3",
                    headers => [ "User-Agent" => "barbot" ]
                );
            is $code, 200;
            is $content, 'foobot, barbot';
        };
    },
    server => sub {
        my $port = shift;
        t::HTTPServer->new(port => $port)->run(sub {
            my $env = shift;
            return [ 200,
                [ 'Content-Length' => length($env->{'HTTP_USER_AGENT'}) ],
                [$env->{'HTTP_USER_AGENT'}]
            ];
        });
    }
);

done_testing;

