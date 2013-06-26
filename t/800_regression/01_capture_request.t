#!perl -Ilib
use strict;
use warnings;
use utf8;
use Test::More;

use Furl;
my $f=Furl->new(capture_request=>1, timeout=>5);
my $r=$f->post("http://example.com.local");
is($r->captured_req_headers, undef);
is($r->captured_req_content, undef);


done_testing;

