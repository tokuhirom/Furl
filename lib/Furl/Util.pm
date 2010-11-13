package Furl::Util;
use strict;
use warnings;
use utf8;

# This class is internal use only.

sub requires {
    my($file, $feature, $library) = @_;
    return if exists $INC{$file};
    unless(eval { require $file }) {
        if ($@ =~ /^Can't locate/) {
        warn $@;
            $library ||= do {
                local $_ = $file;
                s/ \.pm \z//xms;
                s{/}{::}g;
                $_;
            };
            Carp::croak(
                "$feature requires $library, but it is not available."
                . " Please install $library using your prefer CPAN client"
            );
        } else {
            die $@;
        }
    }
}

1;
