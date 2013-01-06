use strict;
use Test::More tests => 1;

BEGIN { use_ok 'Furl' }
diag "Perl/$^V";
diag "Furl/$Furl::VERSION";

for my $optional(qw( Net::IDN::Encode IO::Socket::SSL Compress::Raw::Zlib )) {
    eval qq{ require $optional };
    diag $optional . '/' . ($optional->VERSION || '(not installed)');
}
