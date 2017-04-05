#!perl -w
use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../..";
use t::HTTPServer;

my $n = shift(@ARGV) || 3;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(timeout => 1);
        for (1 .. $n) {
            note "request/$_";
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                );
            is $code, 200, "request()/$_";
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'), 2, 'header'
                or diag(explain($headers));
            is Furl::HTTP::_header_get($headers, 'Connection'), 'keep-alive';
            is $content, 'OK'
                or do{ require Devel::Peek; Devel::Peek::Dump($content) };
        }
        done_testing;
    },
    server => sub {
        my $port = shift;
        t::HTTPServer->new( port => $port )->add_trigger(
            "AFTER_HANDLE_REQUEST" => sub {
                my ( $s, $csock ) = @_;
                $csock->close();
            }
          )->run(
            sub {
                +[
                    200,
                    [ 'Content-Length' => 2, 'Connection' => 'keep-alive' ],
                    ['OK']
                ];
            }
          );
    }
);

