use strict;
use warnings;

use Furl::HTTP;
use Socket ();
use Test::More;
use Test::Requires 'Starlet::Server', 'Plack::Loader';
use Test::TCP;

{
    no warnings 'redefine';
    my $orig = *Starlet::Server::_get_acceptor{CODE};
    *Starlet::Server::_get_acceptor = sub {
        my $acceptor = shift->$orig(@_);
        return sub {
            my ($conn, $peer, $listen) = $acceptor->();
            if ($conn) {
                setsockopt($conn, Socket::SOL_SOCKET, Socket::SO_LINGER, pack('ii', 1, 0))
                    or warn "failed to set SO_LINGER: $!";
                return ($conn, $peer, $listen);
            } else {
                return ();
            }
        }
    };
}

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl::HTTP->new(timeout => 1);
        my ($code, $msg);
        (undef, $code, $msg) = $furl->request(port => $port, host => '127.0.0.1');
        is $code, 200;
        is $msg, 'OK';
        sleep 2;
        (undef, $code, $msg) = $furl->request(port => $port, host => '127.0.0.1');
        is $code, 200;
        is $msg, 'OK';
    },
    server => sub {
        my $port = shift;
        my %args = (
            port => $port,
            keepalive_timeout => 1,
            max_keepalive_reqs => 100,
            max_reqs_per_child => 100,
            max_workers => 1,
        );
        my $app = sub { [200, ['Content-Length' => 2], ['ok']] };
        Plack::Loader->load('Starlet', %args)->run($app);
        exit;
    },
);

done_testing;
