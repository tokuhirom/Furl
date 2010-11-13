use strict;
use warnings;
use Test::More;
use Furl::HTTP;
use Furl::MultipartFormData;
use Test::Requires 'HTTP::Body', 'IO::Callback';
use HTTP::Request::Common;
use File::Temp qw/tempfile/;
use Data::Dumper;
use Scalar::Util qw//;


my $ORIG_CONTENT = 'YEAH!!' x 1024;

# make RFC1867 encoding
my ($fh, $filename) = tempfile(SUFFIX => '.txt');
print {$fh} $ORIG_CONTENT;
close $fh;

subtest 'simple' => sub {
    my ($content, $boundary, $len) = Furl::MultipartFormData::make_multipart_form_data([name => 'foo', pwd => '/etc/passwd']);
    my $hbody = parse_by_http_body($content, $boundary);
    check_parameters($hbody, [name => 'foo', pwd => '/etc/passwd']);
    is $boundary, 'xYzZY';
    isnt $len, 0;
};

subtest 'own boundary' => sub {
    my ($content, $boundary) = Furl::MultipartFormData::make_multipart_form_data([name => 'foo', pwd => '/etc/passwd'], 'HELLO');
    my $hbody = parse_by_http_body($content, $boundary);
    check_parameters($hbody, [name => 'foo', pwd => '/etc/passwd']);
    is $boundary, 'HELLO';
};
subtest 'conflict boundary' => sub {
    my ($content, $boundary) = Furl::MultipartFormData::make_multipart_form_data([name => 'xYzZY']);
    my $hbody = parse_by_http_body($content, $boundary);
    check_parameters($hbody, [name => 'xYzZY']);
    isnt $boundary, 'xYzZY';
};
subtest 'no parameters' => sub {
    my ($content, $boundary) = Furl::MultipartFormData::make_multipart_form_data([]);
    my $hbody = parse_by_http_body($content, $boundary);
    check_parameters($hbody, []);
};

subtest 'file upload' => sub {
    my ($content, $boundary) = Furl::MultipartFormData::make_multipart_form_data([name => 'foo', pwd => [$filename, 'hoge.txt']]);
    my $hbody = parse_by_http_body($content, $boundary);
    check_parameters($hbody, ['name' => 'foo']);
    is($hbody->upload->{'pwd'}->{filename}, 'hoge.txt');
    is($hbody->upload->{'pwd'}->{headers}->{'Content-Type'}, 'text/plain');
    is(slurp($hbody->upload->{'pwd'}->{tempname}), $ORIG_CONTENT);
    is $boundary, 'xYzZY';
};

subtest 'file upload(dynamic)' => sub {
    my ($content, $boundary, $length) = Furl::MultipartFormData::make_multipart_form_data([name => 'foo', pwd => [$filename, 'hoge.txt']], 'xYzZY', 1);
    ok(Scalar::Util::openhandle($content), 'this is fh');
    my $hbody = HTTP::Body->new("multipart/form-data; boundary=$boundary", $length);
    LOOP: while (1) {
        my $ret = read($content, my $buf, 10);
        die $! unless defined $ret;
        last if $ret == 0;
        $hbody->add($buf);
    }
    check_parameters($hbody, ['name' => 'foo']);
    is($hbody->upload->{'pwd'}->{filename}, 'hoge.txt');
    is($hbody->upload->{'pwd'}->{headers}->{'Content-Type'}, 'text/plain');
    is(slurp($hbody->upload->{'pwd'}->{tempname}), $ORIG_CONTENT);
    is $boundary, 'xYzZY';
    isnt $length, 0;
};

done_testing;
exit;

sub slurp {
    my $fname = shift;
    open my $fh, '<', $fname or die "cannot open file: $fname: $!";
    scalar do { local $/; <$fh> };
}

sub parse_by_http_body {
    my ($buf, $boundary) = @_;
    my $body = HTTP::Body->new("multipart/form-data; boundary=$boundary", length($buf));
    $body->add($buf);
    return $body;
}

sub check_parameters {
    my ($hbody, $expected) = @_;
    my $got = [ map { $_ => $hbody->param->{$_} } @{$hbody->param_order }];
    is_deeply($got, $expected) or diag(Dumper($got));
}

