use inc::Module::Install;
use Module::Install::XSUtil 0.30;
use Module::Install::AuthorTests;

name 'Furl';
all_from 'lib/Furl.pm';

use_xshelper;
cc_src_paths qw(xs-src);
cc_warnings;


test_requires 'Test::More' => 0.96; # done_testing, subtest
test_requires 'Test::TCP';
test_requires 'Plack' =>  0.9949;
test_requires 'IO::Socket::INET';
test_requires 'HTTP::Response';

recommends 'Net::IDN::Encode';    # for International Domain Name
recommends 'IO::Socket::SSL';     # for SSL
recommends 'Compress::Raw::Zlib'; # for Content-Encoding

readme_markdown_from 'lib/Furl.pm';
tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
author_tests('xt');

WriteAll;
