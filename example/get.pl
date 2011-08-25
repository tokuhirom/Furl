#!perl -w
use strict;
use Furl;
use HTTP::Response;

my $uri = shift(@ARGV) or die "Usage: $0 URI\n";

my $furl = Furl->new(headers => ['Accept-Encoding' => 'gzip']);
$furl->env_proxy;
print $furl->get($uri)->as_http_response->as_string;
