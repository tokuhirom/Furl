use strict;
use warnings;
use autodie;
use Benchmark ':all';
use LWP::UserAgent;
use WWW::Curl::Easy;
use Furl;
use Child;
use Test::TCP qw/empty_port/;
use Plack::Loader;
use Config;
printf "Perl/%vd on %s\n", $^V, $Config{archname};
printf "Furl/$Furl::VERSION, LWP/$LWP::VERSION, WWW::Curl/$WWW::Curl::VERSION\n";

my $port = empty_port();

my $ua = LWP::UserAgent->new(parse_head => 0, keep_alive => 1);
my $curl = WWW::Curl::Easy->new();
my $furl = Furl->new(parse_header => 0);
my $url = "http://127.0.0.1:$port/";

my $child = Child->new(
    sub {
        Plack::Loader->auto( port => $port )
          ->run(
            sub { exit if $_[0]->{REQUEST_METHOD} eq 'DIE'; [ 200, [], [] ] } );
    }
);
my $proc = $child->start();

cmpthese(
    -1, {
        lwp => sub {
            my $res = $ua->get($url);
        },
        curl => sub {
            my @headers;
            $curl->setopt(CURLOPT_URL, $url);
            $curl->setopt(CURLOPT_HTTPGET, 1);
            $curl->setopt(CURLOPT_HEADER, 0);
            $curl->setopt(CURLOPT_NOPROGRESS, 1);
            $curl->setopt(CURLOPT_HEADERFUNCTION, sub {
                push @headers, @_;
                length($_[0]);
            });
            open my $fh, '<', \my $content;
            $curl->setopt(CURLOPT_WRITEDATA, $fh);
            $curl->perform();
            my $code = $curl->getinfo(CURLINFO_HTTP_CODE);
        },
        furl => sub {
            $furl->request(method => 'GET', url => $url);
        },
    },
);
$furl->request(method => 'DIE', url => $url);

$proc->wait();

