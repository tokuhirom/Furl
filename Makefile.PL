use inc::Module::Install;
use Module::Install::XSUtil 0.30;
use Module::Install::AuthorTests;
name 'Furl';
all_from 'lib/Furl.pm';

requires 'Exporter' => 5.63; # use Exporter 'import';
requires 'Plack' =>  0.9949;

use_xshelper;
cc_src_paths qw(xs-src);
cc_warnings;

test_requires 'Test::TCP';

checklibs lib => 'curl', header => 'curl.h';

readme_markdown_from 'lib/Furl.pm';
tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
test_requires 'Test::More' => 0.96; # done_testing, subtest
author_tests('xt');

makemaker_args(
    CCFLAGS => `curl-config --cflags`,
    LIBS    => `curl-config --libs`,
);
WriteAll;
