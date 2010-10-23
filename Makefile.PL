use inc::Module::Install;
use Module::Install::XSUtil 0.30;
use Module::Install::AuthorTests;

name 'Furl';
all_from 'lib/Furl.pm';

use_xshelper;
cc_src_paths qw(xs-src);
cc_warnings;

requires 'Socket';
requires 'Errno';
requires 'Compress::Raw::Zlib';
requires 'URI::Escape';

test_requires 'Test::More' => 0.96; # done_testing, subtest
test_requires 'Test::TCP';
test_requires 'Plack' =>  0.9949;
test_requires 'IO::Socket::INET';
test_requires 'HTTP::Response';

recommends 'Net::IDN::Encode';
recommends 'IO::Socket::SSL';       # for SSL support

readme_markdown_from 'lib/Furl.pm';
tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
author_tests('xt');

WriteAll;
