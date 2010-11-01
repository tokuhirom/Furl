use inc::Module::Install;
use Module::Install::AuthorTests;
use Module::Install::ReadmeMarkdownFromPod;

name 'Furl';

all_from 'lib/Furl.pm';
readme_markdown_from 'lib/Furl.pm';

requires 'HTTP::Parser::XS' => 0.11;

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

