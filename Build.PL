use strict;
use warnings;
use Module::Build::Pluggable qw(
    CPANfile
    GithubMeta
);

my $build = Module::Build::Pluggable->new(
    license              => 'perl',
    dynamic_config       => 0,

    build_requires => {
        ($ENV{CI} || $ENV{AUTOMATED_TESTING}) ? (
            map { $_ => 0 } qw/Plack Starlet IO::Socket::SSL Test::Perl::Critic Test::Pod Test::LeakTrace Net::DNS::Lite Net::IDN::Encode HTTP::Proxy Plack::Middleware::Deflater IO::Callback/
        ) : ()
    },

    requires             => {
        perl => '5.008005',
    },

    add_to_cleanup => ['.online'],

    no_index    => { 'directory' => [ 'inc' ] },
    name        => 'Furl',
    module_name => 'Furl',

    test_files => (-d '.git' || $ENV{RELEASE_TESTING}) ? 't/ xt/' : 't/',
    recursive_test_files => 1,
   
    create_readme  => 1,
    create_license => 1,
);
$build->create_build_script();
