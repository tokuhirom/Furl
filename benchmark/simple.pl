use strict;
use warnings;
use Benchmark ':all';
use LWP::UserAgent;
use WWW::Curl::Easy 4.14;
use HTTP::Lite;
use Furl;
use Config;

printf `git rev-parse HEAD`;
printf "Perl/%vd on %s\n", $^V, $Config{archname};
printf "Furl/$Furl::VERSION, LWP/$LWP::VERSION, WWW::Curl/$WWW::Curl::VERSION, HTTP::Lite/$HTTP::Lite::VERSION\n";

my $url = shift @ARGV || 'http://192.168.1.3:80/';

my $ua = LWP::UserAgent->new(parse_head => 0, keep_alive => 1);
my $curl = WWW::Curl::Easy->new();
my $furl = Furl->new(parse_header => 0);
my $uri = URI->new($url);
my $host = $uri->host;
my $scheme = $uri->scheme;
my $port = $uri->port;
my $path_query = $uri->path_query;
my $lite = HTTP::Lite->new();

my $server = $ua->get($url)->header('Server');
printf "Server: %s\n", $server || 'unknown';
print "--\n\n";

cmpthese(
    -1, {
        http_lite => sub {
            my $req = $lite->request($url)
                or die;
            $lite->status == 200 or die;
        },
        lwp => sub {
            my $res = $ua->get($url);
            $res->code == 200 or die;
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
        },
        furl => sub {
            my ( $code, $msg, $headers, $content ) = $furl->request(
                method     => 'GET',
                host       => $host,
                port       => $port,
                scheme     => $scheme,
                path_query => $path_query,
                headers    => [ 'Content-Length' => 0 ]
            );
            $code == 200 or die "oops: $code, $content";
        },
    },
);
