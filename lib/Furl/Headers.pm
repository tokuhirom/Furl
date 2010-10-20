package Furl::Headers;
use strict;
use warnings;
use Furl; # to load xs
use List::MoreUtils ();

sub keys {
    List::MoreUtils::uniq($_[0]->_keys);
}

1;
