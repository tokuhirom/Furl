use strict;
use warnings;
use Furl;
use Test::TCP;
use Test::More;
use Test::Requires qw(Plack::Request HTTP::Body), 'HTTP::Request';
use t::HTTPServer;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new();
        my $req = HTTP::Request->new(GET => "http://127.0.0.1:$port/foo");
        $req->headers->header('Host' => '127.0.0.1');
        my $res = $furl->request( $req );
        is $res->code, 200, "HTTP status ok";
    },
    server => sub {
        my $port = shift;
        my $request;
        {
            no warnings 'redefine';
            my $org = t::HTTPServer->can('parse_http_request');
            *t::HTTPServer::parse_http_request = sub {
                $request .= $_[0];
                $org->(@_); 
            };
        }

        t::HTTPServer->new(port => $port)->run(sub {
            my $env = shift;
            my $hash;
            for my $line (split /\n/, $request) {
                my ($k) = (split ':', $line)[0];
                $hash->{$k}++;
            }
            is $hash->{Host}, 1, 'Host header is one';
            is $env->{HTTP_HOST}, "127.0.0.1:$port", 'Host header is ok';
            return [200, ['Content-Length' => 2], ['ok']];
        });
    },
);

done_testing;
