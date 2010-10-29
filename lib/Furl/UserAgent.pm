package Furl::UserAgent;
use strict;
use warnings;
use utf8;
use base qw/Furl/;
use Furl::Response;

no strict 'refs';
for my $meth (qw/get post put delete request/) {
    *{__PACKAGE__ . "::" . $meth} = sub {
        my $self = shift;
        Furl::Response->new(Furl->$meth(@_));
    };
}

1;

