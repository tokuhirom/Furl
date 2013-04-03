use strict;
use warnings;
use Benchmark ':all';
use LWP::UserAgent;
use WWW::Curl::Easy 4.14;
use HTTP::Lite;
use Furl::HTTP qw/HEADERS_NONE HEADERS_AS_ARRAYREF/;
use Furl;
use Config;
use Getopt::Long;

GetOptions(
    'busize=i' => \my $bufsize,
);

printf `git rev-parse HEAD`;
printf "Perl/%vd on %s\n", $^V, $Config{archname};
printf "Furl/$Furl::VERSION, LWP/$LWP::VERSION, WWW::Curl/$WWW::Curl::VERSION, HTTP::Lite/$HTTP::Lite::VERSION, libcurl[@{[ WWW::Curl::Easy::version() ]}]\n";

my $url = shift @ARGV || 'http://192.168.1.3:80/';

my $ua = LWP::UserAgent->new(parse_head => 0, keep_alive => 1);
my $curl = WWW::Curl::Easy->new();
my $furl_low = Furl::HTTP->new(header_format => HEADERS_NONE);
my $furl_high = Furl->new();
$furl_high->{bufsize} = $bufsize if defined $bufsize;
$furl_low->{bufsize} = $bufsize if defined $bufsize;
my $uri = URI->new($url);
my $host = $uri->host;
my $scheme = $uri->scheme;
my $port = $uri->port;
my $path_query = $uri->path_query;
my $lite = HTTP::Lite->new();
$lite->http11_mode(1);

my $res = $ua->get($url);
print "--\n";
print $res->headers_as_string;
print "--\n";
printf "bufsize: %d\n", $furl_low->{bufsize};
print "--\n\n";
my $body_content_length = length($res->content);
$body_content_length == $res->content_length or die;

cmpthese(
    -1, {
        http_lite => sub {
            my $req = $lite->request($url)
                or die;
            $lite->status == 200 or die;
            length($lite->body) == $body_content_length or die "Lite failed: @{[ length($lite->body) ]} != $body_content_length";
            $lite->reset(); # This is *required* for re-use instance.
        },
        lwp => sub {
            my $res = $ua->get($url);
            $res->code == 200 or die;
            length($res->content) == $body_content_length or die;
        },
        curl => sub {
            my @headers;
            $curl->setopt(CURLOPT_HEADER, 0);
            $curl->setopt(CURLOPT_NOPROGRESS, 1);
            $curl->setopt(CURLOPT_URL, $url);
            $curl->setopt(CURLOPT_HTTPGET, 1);
            $curl->setopt(CURLOPT_HEADERFUNCTION, sub {
                push @headers, @_;
                length($_[0]);
            });
            my $content = '';
            $curl->setopt(CURLOPT_WRITEDATA, \$content);
            my $ret = $curl->perform();
            $ret == 0 or die "$ret : " . $curl->strerror($ret);
            my $code = $curl->getinfo(CURLINFO_HTTP_CODE);
            $code == 200 or die "oops: $code";
            length($content) == $body_content_length or die;
        },
        furl_high => sub {
            my $res = $furl_high->request(
                method     => 'GET',
                host       => $host,
                port       => $port,
                scheme     => $scheme,
                path_query => $path_query,
                headers    => [ 'Content-Length' => 0 ]
            );
            $res->code == 200 or die "oops";
            length($res->content) == $body_content_length or die;
        },
        furl_low => sub {
            my ( $version, $code, $msg, $headers, $content ) = $furl_low->request(
                method     => 'GET',
                host       => $host,
                port       => $port,
                scheme     => $scheme,
                path_query => $path_query,
                headers    => [ 'Content-Length' => 0 ]
            );
            $code == 200 or die "oops: $code, $content";
            length($content) == $body_content_length or die;
        },
    },
);
