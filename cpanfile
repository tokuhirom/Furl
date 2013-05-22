requires 'perl', 5.008_001;

requires 'HTTP::Parser::XS' => 0.11;
requires 'Mozilla::CA';
requires 'MIME::Base64';
requires 'Class::Accessor::Lite';
requires 'Encode';
requires 'Scalar::Util';
requires 'Socket';
requires 'Time::HiRes';

suggests 'HTTP::Headers'; # Furl::Headers
suggests 'HTTP::Request'; # Furl::Request
suggests 'HTTP::Response'; # Furl::Response

recommends 'Net::IDN::Encode';    # for International Domain Name
recommends 'IO::Socket::SSL';     # for SSL
recommends 'Compress::Raw::Zlib'; # for Content-Encoding

on test => sub {
    requires 'Test::More' => 0.96;    # done_testing, subtest
    requires 'Test::TCP'  => 1.06;
    requires 'Test::Requires';
    requires 'File::Temp';
    suggests 'Test::Fake::HTTPD';
    suggests 'HTTP::Proxy';
    suggests 'HTTP::Server::PSGI';
    suggests 'Plack::Loader';
    suggests 'Plack::Request';
    suggests 'Starlet::Server';
    suggests 'Test::SharedFork';
    suggests 'URI';
    suggests 'parent';
    suggests 'Plack';
    suggests 'Test::Valgrind';
};

on develop => sub {
    suggests 'Child';
    suggests 'Getopt::Long';
    suggests 'HTTP::Lite';
    suggests 'LWP::UserAgent';
    suggests 'Plack::Loader';
    suggests 'Starman';
    suggests 'Test::More';
    suggests 'Test::suggests';
    suggests 'Test::TCP';
    suggests 'URI';
    suggests 'WWW::Curl::Easy', '4.14';
    suggests 'autodie';
    suggests 'parent';
};

