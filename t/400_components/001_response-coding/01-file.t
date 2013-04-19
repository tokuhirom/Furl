#!perl

use strict;
use warnings;
use Furl;
use File::Spec;
use Encode;
use Cwd;
use Test::Requires 'Test::Fake::HTTPD', 'URI';
use URI;
use Test::More tests => 13;
use Test::TCP;
use Test::Fake::HTTPD;

my $ua = Furl->new;
my $cwd = getcwd;

#BEGIN{
#    package LWP::Protocol;
#    $^W = 0;
#}

my $httpd = run_http_server {
    my $req = shift;
    my $path = 't/400_components/001_response-coding' . $req->uri->path;
    open my $fh, '<', $path or die "$path: $!";
    return [ 200, [ 'Content-Type' => 'text/html' ], $fh ];
};
note $httpd->host_port;

for my $meth (qw/charset encoder encoding decoded_content/){
    can_ok('Furl::Response', $meth);
}

my %charset = qw(
		 UTF-8        utf-8-strict;
		 EUC-JP       EUC-JP
		 Shift_JIS    SHIFT_JIS
		 ISO-2022-JP  ISO-2022-JP
	       );

my %filename = qw(
	      UTF-8        t-utf-8.html
	      EUC-JP       t-euc-jp.html
	      Shift_JIS    t-shiftjis.html
	      ISO-2022-JP  t-iso-2022-jp.html
	     );

for my $charset (sort keys %charset){
    my $uri = URI->new('http://' . $httpd->host_port);
    $uri->path(File::Spec->catfile($filename{$charset}));
    my $res;
    {
        local $^W = 0; # to quiet LWP::Protocol
        $res = $ua->get($uri);
    }
    die unless $res->is_success;
    is $res->charset, $charset, "\$res->charset eq '$charset'";
    my $canon = find_encoding($charset)->name;
    is $res->encoding, $canon, "\$res->encoding eq '$canon'"; 
}

my $uri = URI->new('http://' . $httpd->host_port);
$uri->path("t-null.html");
my $res = $ua->get($uri);
die unless $res->is_success;
if (defined $res->encoding){
    is $res->encoding, "ascii", "res->encoding is ascii";
}else{
    ok !$res->encoding, "res->encoding is undef";
}
