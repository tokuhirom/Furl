use inc::Module::Install;
name 'Furl';
all_from 'lib/Furl.pm';

requires 'Exporter' => 5.63; # use Exporter 'import';
requires 'Plack' =>  0.9949;

test_requires 'Test::TCP';

readme_markdown_from 'lib/Furl.pm';
tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
test_requires 'Test::More' => 0.96; # done_testing, subtest
author_tests('xt');
WriteAll;
