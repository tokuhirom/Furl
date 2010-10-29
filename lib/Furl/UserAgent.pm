package Furl::UserAgent;
use strict;
use warnings;
use utf8;
use base qw/Furl/;
use Furl::Response;

sub new {
    my $class = shift;
    return $class->SUPER::new(header_format => Furl::FORMAT_HASHREF(), @_);
}

no strict 'refs';
for my $meth (qw/get post put delete request/) {
    *{__PACKAGE__ . "::" . $meth} = sub {
        my $self = shift;
        Furl::Response->new(Furl->$meth(@_));
    };
}

1;

