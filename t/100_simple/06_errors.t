use strict;
use warnings;
use Furl;
use Test::TCP;
use Test::More;

use Plack::Request;
use Errno ();

{
    my $furl = Furl->new();
    eval {
        $furl->request();
    };
    like $@, qr/missing host name/i, 'missuse';

    eval {
        $furl->get('ftp://ftp.example.com/');
    };
    like $@, qr/unsupported scheme/i, 'missuse';

    eval {
        $furl->get('http://./');
    };
    like $@, qr/cannot resolve host name/i, 'missuse';

    foreach my $bad_url(qw(
        hogehoge
        http://example.com:80foobar
        http://example.com:
    )) {
        eval {
            $furl->get($bad_url);
        };
        like $@, qr/malformed URL/, "malformed URL: $bad_url";
    }
}

my $n = shift(@ARGV) || 3;

my $fail_on_syswrite = 1;
{
    package Errorneous::Socket;
    use parent qw(IO::Socket::INET);
    sub syswrite {
        my($sock, $buff, $len, $off) = @_;
        if($fail_on_syswrite) {
            $sock->SUPER::syswrite($buff, $len - 1, $off);
            close $sock;
            $! = Errno::EPIPE;
            return undef;
        }
        return $sock->SUPER::syswrite($buff, $len, $off);
    }
    package Errorneous::Server;
    use parent qw(HTTP::Server::PSGI);
    sub setup_listener {
        my $self = shift;
        $self->SUPER::setup_listener(@_);
        bless $self->{listen_sock}, 'Errorneous::Socket';
        ::note 'Errorneous::Server listening';
    }
}

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new();
        for (1..$n) {
            my ( $code, $msg, $headers, $content ) =
                $furl->request(
                    port       => $port,
                    path_query => '/foo',
                    host       => '127.0.0.1',
                    headers    => [ "X-Foo" => "ppp" ]
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
        Errorneous::Server->new(port => $port)->run(sub {
            my $env = shift;
            #note explain $env;
            my $req = Plack::Request->new($env);
            is $req->header('X-Foo'), "ppp" if $env->{REQUEST_URI} eq '/foo';
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}) ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);

