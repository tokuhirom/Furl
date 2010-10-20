use strict;
use warnings;
use Benchmark ':all';
use LWP::UserAgent;
use WWW::Curl::Easy;
use Furl;

my $ua = LWP::UserAgent->new(parse_head => 0, keep_alive => 1);
my $curl = WWW::Curl::Easy->new();
my $furl = Furl->new(parse_header => 0);
my $url = shift @ARGV || 'http://192.168.1.3:80/';

cmpthese(
    -1, {
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
            open my $fh, '>', \my $content;
            $curl->setopt(CURLOPT_WRITEDATA, $fh);
            my $ret = $curl->perform();
            $ret == 0 or die "$ret : " . $curl->strerror($ret);
            my $code = $curl->getinfo(CURLINFO_HTTP_CODE);
            $code == 200 or die "oops: $code";
        },
        furl => sub {
            my ($code, $headers, $content) = $furl->request(method => 'GET', url => $url, headers => ['Connection: Keep-Alive', 'Keep-Alive: 300']);
            $code == 200 or die "oops: $code, $content";
        },
    },
);
