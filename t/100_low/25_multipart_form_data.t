use strict;
use warnings;
use Test::More;
use Test::TCP;
use Test::Requires 'IO::Callback', 'Plack::Loader', 'Plack::Request';
use Furl::HTTP;
use Furl::MultipartFormData qw/make_multipart_form_data/;
use File::Temp qw/tempfile/;

my $n = shift(@ARGV) || 3;

my $ORIG_CONTENT = 'YEAH!!' x 1;
# make RFC1867 encoding
my ($fh, $filename) = tempfile(SUFFIX => '.txt');
print {$fh} $ORIG_CONTENT;
close $fh;

test_tcp(
    client => sub {
        my $port = shift;
        my $furl = Furl->new(bufsize => 10, timeout => 3);

        note 'normal upload';
        for (1 .. $n) {
            my ($content, $boundary, $len) = make_multipart_form_data([name => 'JOHN', data => [$filename]]);
            ok $boundary;
            ok $len, 'ok len';
            my $res =
                $furl->request(
                    port       => $port,
                    method     => 'POST',
                    path_query => '/normal',
                    host       => '127.0.0.1',
                    headers    => [
                        'Content-Type' => "multipart/form-data; boundary=$boundary",
                        'Content-Length' => $len,
                    ],
                    content    => $content,
                );
            is $res->code, 200, "request()/$_";
        }

        note 'streaming upload';
        for (1 .. $n) {
            my ($content, $boundary, $len) = make_multipart_form_data([name => 'JOHN', data => [$filename]]);
            ok $boundary;
            ok $len, 'ok len';
            my $res =
                $furl->request(
                    port       => $port,
                    method     => 'POST',
                    path_query => '/normal',
                    host       => '127.0.0.1',
                    headers    => [
                        'Content-Type' => "multipart/form-data; boundary=$boundary",
                        'Content-Length' => $len,
                    ],
                    content    => $content,
                );
            is $res->code, 200, "request()/$_";
        }

        done_testing;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->auto(port => $port)->run(sub {
            my $env = shift;
            my $req = Plack::Request->new($env);
            is $req->content_type, 'multipart/form-data; boundary=xYzZY';
            is $req->param('name'), 'JOHN';
            my $data = $req->upload('data');
            ok $data;
            is $data->size, length($ORIG_CONTENT);
            open my $fh, '<', $data->path or die;
            my $body = do { local $/; <$fh> };
            is $body, $ORIG_CONTENT;
            close $fh;
            return [ 200,
                [ 'Content-Length' => length($env->{REQUEST_URI}) ],
                [$env->{REQUEST_URI}]
            ];
        });
    }
);

