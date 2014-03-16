use strict;
use warnings;
use utf8;
use Test::More;
use t::Util;
use Furl;
use Test::TCP;
use Test::Requires qw(Plack::Request Test::MockTime HTTP::Body Plack::Loader), 'Plack';

Test::MockTime::set_absolute_time('2014-03-15T01:02:31Z');

test_tcp(
    client => sub {
        my $port = shift;

        local $Furl::TRACE_FILE = File::Temp->new();
        my $furl = Furl->new();
        my $url = "http://127.0.0.1:$port";

        {
            my $res = $furl->post("http://127.0.0.1:$port", ['X-Foo' => 'Bar'], ['A' => 'B']);
            is $res->status, 200;

            my $src = slurp($Furl::TRACE_FILE);
            like $src, qr/X-Foo: Bar/; # request header
            like $src, qr/A=B/; # request content
            like $src, qr/OK!!!/; # response content
        }

        {
            my $res = $furl->get("http://127.0.0.1:$port", ['X-Moe' => 'foo']);
            is $res->status, 200;

            my $src = slurp($Furl::TRACE_FILE);
            like $src, qr/X-Moe: foo/; # request header
            like $src, qr/OK!!!/; # response content

            note $src;
        }

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto( port => $port )->run(sub {
            my $env     = shift;
            return [
                200,
                [ 'Content-Length' => 5 ],
                ['OK!!!']
            ];
        });
    }
);

sub slurp {
    my $fname = shift;
    open my $fh, '<', $fname
        or Carp::croak("Can't open '$fname' for reading: '$!'");
    scalar(do { local $/; <$fh> })
}

__END__
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
POST / HTTP/1.1
Connection: keep-alive
User-Agent: Furl::HTTP/<<VERSION>>
X-Foo: Bar
Content-Type: application/x-www-form-urlencoded
Content-Length: 3
Host: 127.0.0.1:<<PORT>>


A=B
================================================================================
200 OK
content-length: 2
date: Sat, 15 Mar 2014 01:02:31 GMT
server: HTTP::Server::PSGI

OK
<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
