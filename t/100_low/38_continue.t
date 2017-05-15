use strict;
use warnings;
use utf8;
use Furl::HTTP;
use Test::TCP;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../..";
use t::HTTPServer;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(bufsize => 10, timeout => 3);
        my ( undef, $code, $msg, $headers, $content ) =
            $furl->request(
                port       => $port,
                path_query => '/100',
                host       => '127.0.0.1',
                headers    => []
            );
        is $code, 200;
        is $msg, 'OK';
        is $content, 'OK';

        ( undef, $code, $msg, $headers, $content ) =
            $furl->request(
                port       => $port,
                path_query => '/101',
                host       => '127.0.0.1',
                headers    => []
            );
        is $code, 200;
        is $msg, 'OK';
        is $content, 'OK';
        done_testing;
    },
    server => sub {
        my $port = shift;
        my $server = t::HTTPServer->new(port => $port);
        $server->add_trigger(BEFORE_CALL_APP => sub {
            my ($self, $csock, $env) = @_;
            my $code = $env->{PATH_INFO} || '100';
            $code =~ s!/!!g;
            my $status = $t::HTTPServer::STATUS_CODE{$code};
            $self->write_all($csock, "HTTP/1.1 $code $status\015\012\015\012");
        });
        $server->run(sub {
            my $env = shift;
            return [ 200, [], ['OK'] ];
        });
    }
);
