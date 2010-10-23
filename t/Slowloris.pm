package Slowloris;
use strict;
use warnings;

our $WriteBytes   = 1;
our $SleepByWrite = 0;

package Slowloris::Socket;
use parent qw(IO::Socket::INET);
use Time::HiRes qw(sleep);
sub syswrite {
    my($sock, $buff, $len, $off) = @_;
    my $w = $off;
    while($off < $len) {
        $off += $sock->SUPER::syswrite($buff, $Slowloris::WriteBytes, $off);
        sleep($SleepByWrite) if $SleepByWrite;
    }
    return $off - $w;
}

package Slowloris::Server;
use parent qw(HTTP::Server::PSGI);
sub setup_listener {
    my $self = shift;
    $self->SUPER::setup_listener(@_);
    bless $self->{listen_sock}, 'Slowloris::Socket';
}

1;

