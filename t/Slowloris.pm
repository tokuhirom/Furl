package t::Slowloris;
use strict;
use warnings;

package Slowloris;
use Test::SharedFork;

our $WriteBytes   = 1;
our $SleepBeforeWrite = 0;
our $SleepBeforeRead  = 0;

package Slowloris::Socket;
use parent qw(IO::Socket::INET);
use Time::HiRes qw(sleep);
sub syswrite {
    my($sock, $buff, $len, $off) = @_;
    sleep $SleepBeforeWrite if $SleepBeforeWrite;
    my $w = $off;
    while($off < $len) {
        my $n = $sock->SUPER::syswrite($buff, $Slowloris::WriteBytes, $off);
        defined($n) or return undef;
        $off += $n;

    }
    return $off - $w;
}

sub sysread {
    my $sock = shift;
    sleep $SleepBeforeRead if $SleepBeforeRead;
    return $sock->SUPER::sysread(@_);
}

package Slowloris::Server;
use parent qw(HTTP::Server::PSGI);

sub setup_listener {
    my $self = shift;
    $self->SUPER::setup_listener(@_);
    bless $self->{listen_sock}, 'Slowloris::Socket';
}

1;

