use strict;
use warnings;
use Furl;

my $url = shift @ARGV || 'http://127.0.0.1:80/';

my $furl = Furl->new(parse_header => 0);
for (1..1000) {
    my ($code, $headers, $content) = $furl->request(
        method  => 'GET',
        url     => $url,
    );
    $code == 200 or die "oops : $code, $content";
}

