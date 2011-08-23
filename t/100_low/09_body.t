use strict;
use warnings;
use Furl::HTTP;
use Test::TCP;
use Test::Requires qw(Plack::Request HTTP::Body), 'Plack';
use Plack::Loader;
use Test::More;
use Fcntl qw(SEEK_SET);

use Plack::Request;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(bufsize => 80);

        for my $x(1, 1000) {
            my $req_content = "WOWOW!" x $x;
            note 'request content length: ', length $req_content;
            open my $req_content_fh, '<', \$req_content or die "oops";
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    method     => 'POST',
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                    headers    => [ "X-Foo" => "ppp" ],
                    content    => $req_content_fh,
                );
            is $code, 200, "request()";
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'),
                length($req_content);
            is $content, $req_content
                or do{ require Devel::Peek; Devel::Peek::Dump($content) };
        }

        {
            open my $req_content_fh, '<', $0 or die "oops";
            note 'request $0: ', -s $req_content_fh;
            my $req_content = do{ local $/; <$req_content_fh> };
            seek $req_content_fh, 0, SEEK_SET;
            my ( undef, $code, $msg, $headers, $content ) =
                $furl->request(
                    method     => 'POST',
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                    headers    => [ "X-Foo" => "ppp" ],
                    content    => $req_content_fh,
                );
            is $code, 200, "request()";
            is $msg, "OK";
            is Furl::HTTP::_header_get($headers, 'Content-Length'),
                length($req_content);
            is $content, $req_content
                or do{ require Devel::Peek; Devel::Peek::Dump($content) };
        }

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            #note explain $env;
            my $req = Plack::Request->new($env);
            is $req->header('X-Foo'), "ppp" if $env->{REQUEST_URI} eq '/foo';
            like $req->header('User-Agent'), qr/\A Furl::HTTP /xms;
            return [ 200,
                [ 'Content-Length' => length($req->content) ],
                [$req->content]
            ];
        });
    }
);

