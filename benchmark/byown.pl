use strict;
use warnings;
use autodie;
use Benchmark ':all';
use Starman;
use LWP::UserAgent;
use WWW::Curl::Easy 4.14;
use Furl::HTTP;
use Child;
use Test::TCP qw/empty_port/;
use Plack::Loader;
use Config;
use HTTP::Lite;

printf "Perl/%vd on %s\n", $^V, $Config{archname};
printf "Furl/$Furl::VERSION, LWP/$LWP::VERSION, WWW::Curl/$WWW::Curl::VERSION, HTTP::Lite/$HTTP::Lite::VERSION, libcurl[@{[ WWW::Curl::Easy::version() ]}]\n";

my $port = empty_port();

my $ua = LWP::UserAgent->new(parse_head => 0, keep_alive => 1);
my $curl = WWW::Curl::Easy->new();
my $furl = Furl::HTTP->new(parse_header => 0);
my $url = "http://127.0.0.1:$port/foo/bar";

my $child = Child->new(
    sub {
        Plack::Loader->load( 'Starman', port => $port )
          ->run(
            sub { [ 200, ['Content-Length' => length('Hi')], ['Hi'] ] } );
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
            my $content = '';
            $curl->setopt(CURLOPT_WRITEDATA, \$content);
            $curl->perform();
            my $code = $curl->getinfo(CURLINFO_HTTP_CODE);
        },
        furl => sub {
            $furl->request(method => 'GET', url => $url);
        },
    },
);

$proc->kill('TERM');

