use strict;
use warnings;
use Furl qw/HEADER_NONE HEADERS_AS_ARRAYREF/;
use URI;

my $url = shift @ARGV || 'http://127.0.0.1:80/';
my $uri = URI->new($url);
my $host       = $uri->host;
my $port       = $uri->port;
my $path_query = $uri->path_query;

my $furl = Furl->new(header_format => HEADER_NONE, bufsize => 10_000_000);
for (1..1000) {
    my ( $code, $headers, $content ) = $furl->request(
        method     => 'GET',
        host       => $host,
        port       => $port,
        path_query => $path_query,
    );
    $code == 200 or die "oops : $code, $content";
}

