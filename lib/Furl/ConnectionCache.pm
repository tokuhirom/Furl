package Furl::ConnectionCache;
use strict;
use warnings;
use utf8;

sub new { bless [''], shift }

sub steal {
    my ($self, $host, $port) = @_;
    if ($self->[0] eq "$host:$port") {
        my $sock = $self->[1];
        @{$self} = ('');
        return $sock;
    } else {
        return undef;
    }
}

sub push {
    my ($self, $host, $port, $sock) = @_;
    $self->[0] = "$host:$port";
    $self->[1] = $sock;
}

1;

