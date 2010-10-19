use strict;
use warnings;
use autodie;
use Furl;

my $furl = Furl->new(parse_header => 0);
for (1..1000) {
    $furl->request(method => 'GET', host => '127.0.0.1', port => 80);
}

