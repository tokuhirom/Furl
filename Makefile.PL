use inc::Module::Install;
use Module::Install::AuthorTests;
use Module::Install::ReadmeMarkdownFromPod;

name 'Furl';

all_from 'lib/Furl.pm';
readme_markdown_from 'lib/Furl.pm';

requires 'HTTP::Parser::XS' => 0.11;

test_requires 'Test::More' => 0.96;    # done_testing, subtest
test_requires 'Test::TCP'  => 1.06;
test_requires 'Test::Requires';

recommends 'Net::IDN::Encode';    # for International Domain Name
recommends 'IO::Socket::SSL';     # for SSL
recommends 'Compress::Raw::Zlib'; # for Content-Encoding

tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
author_tests('xt');

repository 'http://github.com/tokuhirom/p5-Furl/';
bugtracker 'http://github.com/tokuhirom/p5-Furl/issues';

clean_files '.online';

WriteAll;

