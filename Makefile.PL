use inc::Module::Install;
use Module::Install::XSUtil 0.30;
use Module::Install::AuthorTests;

name 'Furl';
all_from 'lib/Furl.pm';

use_xshelper;
cc_src_paths qw(xs-src);
cc_warnings;

requires 'Exporter' => 5.63; # use Exporter 'import';
requires 'Plack' =>  0.9949;

requires 'IO::Socket::INET';

test_requires 'Test::TCP';

readme_markdown_from 'lib/Furl.pm';
tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
test_requires 'Test::More' => 0.96; # done_testing, subtest
author_tests('xt');

WriteAll;
