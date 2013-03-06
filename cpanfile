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
