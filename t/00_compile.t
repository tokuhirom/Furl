use strict;
use Test::More tests => 1;

BEGIN { use_ok 'Furl' }
diag "Furl/$Furl::VERSION";
eval { require IO::Socket::SSL }
    and diag "IO::Socket::SSL/$IO::Socket::SSL::VERSION";
