package Furl;
use strict;
use warnings;
use 5.00800;
our $VERSION = '0.01';

use XSLoader;
XSLoader::load('Furl', $VERSION);

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    my $agent = __PACKAGE__ . '/' . $VERSION;
    my $timeout = $args{timeout} || 10;
    bless {
        parse_header => 1,
        curl         => Furl::_new_curl($agent, $timeout),
        %args
    }, $class;
}

sub request {
    my $self = shift;
    my %args = @_;

    my $url = do {
        if ($args{url}) {
            $args{url};
        } else {
            my $port = $args{port} || 80;
            my $path = $args{path} || '/';
            "http://$args{host}:$port$path";
        }
    };
    my $content = $args{content} || '';
    my @headers = @{$args{headers} || []};

    my $method = $args{method} || 'GET';

    my ( $res_code, $res_headers, $res_content ) =
      Furl::_request( $self->{curl}, $url, \@headers, $method, $content,
        undef );

    pop @$res_headers;
    shift @$res_headers;
    if ($self->{parse_header}) {
        @$res_headers = map { s/\015?\012$//; split /\s*:\s*/, $_, 2 } @$res_headers;
    }

    return ($res_code, $res_headers, $res_content);
}

1;
__END__

=encoding utf8

=head1 NAME

Furl -

=head1 SYNOPSIS

    use Furl;

    my $furl = Furl->new(agent => ...);
    my ($code, $headers, $body) = $furl->request(
        method => 'GET',
        host   => 'example.com',
        port   => 80,
        path   => '/'
    );
    # or
    my ($code, $headers, $body) = $furl->request(
        method => 'GET',
        host   => 'example.com',
        port   => 80,
        path   => '/'
        save_to_tmpfile => 1,
    );

=head1 DESCRIPTION

Furl is yet another http client library.

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
