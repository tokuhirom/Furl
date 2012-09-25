use strict;
use warnings;
use Test::More;

use Furl;

subtest 'agent' => sub {
    my $furl = Furl->new( agent => 'Furl/test' );
    is $furl->agent, "Furl/test", 'get User-Agent';

    $furl->agent('Furl/new');
    is $furl->agent, "Furl/new", 'set new User-Agent';
};

done_testing;
