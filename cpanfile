requires 'HTTP::Parser::XS' => 0.11;
requires 'Mozilla::CA';
requires 'MIME::Base64';
requires 'Class::Accessor::Lite';

recommends 'Net::IDN::Encode';    # for International Domain Name
recommends 'IO::Socket::SSL';     # for SSL
recommends 'Compress::Raw::Zlib'; # for Content-Encoding

on test => sub {
    requires 'Test::More' => 0.96;    # done_testing, subtest
    requires 'Test::TCP'  => 1.06;
    requires 'Test::Requires';
};

on configure => sub {
    requires 'Module::Build' => 0.40;
    requires 'Module::Build::Pluggable';
    requires 'Module::Build::Pluggable::GithubMeta';
    requires 'Module::Build::Pluggable::CPANfile';
    requires 'Module::Build::Pluggable::ReadmeMarkdownFromPod';
};
