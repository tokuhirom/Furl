requires 'HTTP::Parser::XS' => 0.11;
requires 'Mozilla::CA';
requires 'MIME::Base64';
requires 'Class::Accessor::Lite';
requires 'Encode';
requires 'Scalar::Util';
requires 'Socket';
requires 'Time::HiRes';

recommends 'HTTP::Headers'; # Furl::Headers
recommends 'HTTP::Request'; # Furl::Request
recommends 'HTTP::Response'; # Furl::Response

recommends 'Net::IDN::Encode';    # for International Domain Name
recommends 'IO::Socket::SSL';     # for SSL
recommends 'Compress::Raw::Zlib'; # for Content-Encoding

on test => sub {
    requires 'Test::More' => 0.96;    # done_testing, subtest
    requires 'Test::TCP'  => 1.06;
    requires 'Test::Requires';
    requires 'Test::Fake::HTTPD';
    recommends 'File::Temp';
    recommends 'HTTP::Proxy';
    recommends 'HTTP::Server::PSGI';
    recommends 'Plack::Loader';
    recommends 'Plack::Request';
    recommends 'Starlet::Server';
    recommends 'Test::SharedFork';
    recommends 'URI';
    recommends 'parent';
    recommends 'Plack';
    recommends 'Test::Valgrind';
};

on develop => sub {
    requires 'Child';
    requires 'Getopt::Long';
    requires 'HTTP::Lite';
    requires 'LWP::UserAgent';
    requires 'Plack::Loader';
    requires 'Starman';
    requires 'Test::More';
    requires 'Test::Requires';
    requires 'Test::TCP';
    requires 'URI';
    requires 'WWW::Curl::Easy', '4.14';
    requires 'autodie';
    requires 'parent';
};

