use strict;
use warnings;

use Furl::HTTP;
use Test::More;
use Test::Requires qw(Plack::Request HTTP::Body), qw(Net::DNS::Lite);
use Time::HiRes qw(time sleep);

my $n = shift(@ARGV) || 2;

# TODO add proxy tests

{
    my $furl = Furl::HTTP->new(
        inet_aton => sub { Net::DNS::Lite::inet_aton(@_) },
    );
    for (1 .. $n) {
        my $start_at = time;
        my (undef, $code, $msg, $headers, $content) = $furl->request(
            host       => 'google.com', # authoritative dns does not respond
            port       => 80,
            path_query => '/',
        );
        my $elapsed = time - $start_at;
        is $code, 200, "request/$_";
        is ref($headers), 'ARRAY';
    }
}

note 'dns timeout';
{
    my $called_inet_aton = 0;
    my $furl = Furl::HTTP->new(
        timeout   => 1,
        inet_aton => sub {
            # mimic timeout
            my ($name, $timeout) = @_;
            $called_inet_aton++;
            sleep $timeout;
            return undef;
        }
    );
    for (1 .. $n) {
        my $start_at = time;
        my (undef, $code, $msg, $headers, $content) = $furl->request(
            host       => 'www.google.com.', # would fail anyway, since inet_aton always returns timeout
            port       => 80,
            path_query => '/foo',
        );
        my $elapsed = time - $start_at;
        is $code, 500, "request/$_";
        like $msg, qr/Internal Response: Cannot resolve host name: www\.google\.com/;
        is ref($headers), 'ARRAY';
        ok $content, "content: $content";
        ok 0.5 <= $elapsed && $elapsed < 1.5, "elapsed: $elapsed";
        note "inet_aton calling count: $called_inet_aton";
    }
}

done_testing;
