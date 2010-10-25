#!perl -w
use strict;
use Benchmark qw(:all);
use Data::Dumper;
use Furl;
use HTTP::Response::Parser qw(parse_http_response);

 # based on `curl -v http://example.com/ >/dev/null`
my $header = <<'H';
HTTP/1.1 200 OK
Server: Apache
Last-Modified: Fri, 30 Jul 2010 15:30:18 GMT
ETag: "573c1-254-48c9c87349680"
Accept-Ranges: bytes
Content-Type: text/html; charset=UTF-8
Connection: Keep-Alive
Date: Mon, 25 Oct 2010 05:45:42 GMT
Age: 13     
Content-Length: 596

H
$header =~ s/\015/\012\015/g;

sub furl_phr{
    my %headers;
    my %notused;
    my($minor, $status, $msg, $ret) = Furl::parse_http_response(
        $_[0], 0, \%headers, \%notused);
    $_[1]{_rc}       = $status;
    $_[1]{_msg}      = $msg;
    $_[1]{_protocol} = 'HTTP/1.' . $minor;
    $_[1]{_headers}  = \%headers;
#
#    %{ $_[1] } = (
#        _rc       => $status,
#        _msg      => $msg,
#        _protocol => 'HTTP/1'.$minor,
#        _headers  => \%headers,
#    );
    return $ret;
}
my %h;
my $ret;
($ret = furl_phr($header, \%h)) > 0 or die $ret;
my $furl_phr =  Dumper \%h;
($ret = parse_http_response($header, \%h)) > 0 or die $ret;
my $phr = Dumper \%h;
$furl_phr eq $phr or die $furl_phr, $phr;

cmpthese -1, {
    Furl => sub {
        my %res;
        my %headers;
        my %notused;
        my($minor, $status, $msg, $ret) = Furl::parse_http_response(
            $header, 0, \%headers, \%notused);
        $res{_rc}       = $status;
        $res{_msg}      = $msg;
        $res{_protocol} = 'HTTP/1.' . $minor;
        $res{_headers}  = \%headers;
    },
    
    HRP => sub {
        my %h;
        parse_http_response($header, \%h) > 0 or die;
    },
};


