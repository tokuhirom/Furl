use inc::Module::Install;
use Module::Install::XSUtil 0.36;
use Module::Install::AuthorTests;
use Module::Install::ReadmeMarkdownFromPod;

name 'Furl';
reference_module 'lib/Furl.pm'; # all_from, readme_from, readme_markdown_from

use_xshelper;
cc_src_paths qw(xs);
cc_warnings;

test_requires 'Test::More' => 0.96; # done_testing, subtest
test_requires 'Test::TCP' => 1.06;
test_requires 'Plack' =>  0.9949;
test_requires 'IO::Socket::INET';
test_requires 'HTTP::Request';
test_requires 'HTTP::Response';

recommends 'Net::IDN::Encode';    # for International Domain Name
recommends 'IO::Socket::SSL';     # for SSL
recommends 'Compress::Raw::Zlib'; # for Content-Encoding

tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
author_tests('xt');

clean_files '.online';

WriteAll;

