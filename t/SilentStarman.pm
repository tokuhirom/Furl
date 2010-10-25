package SlientStarman;
use strict;
use Starman::Server;
@Starman::Server::ISA = (__PACKAGE__);

our @ISA = qw(Net::Server::PreFork);
sub run {
    my($self, %args) = @_;
    $args{log_level} = 0;
    $self->SUPER::run(%args);
}

1;
