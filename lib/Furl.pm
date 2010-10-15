package Furl;
use strict;
use warnings;
use 5.00800;
our $VERSION = '0.01';
use LWP::UserAgent;

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    bless {
        agent => __PACKAGE__ . '/' . $VERSION,
        %args
    }, $class;
}

sub request {
    my $self = shift;
    my %args = @_;

    my $port = $args{port} || 80;
    my $path = $args{path} || '/';
    my $url = "http://$args{host}:$port$path";

    my $method = $args{method} || 'GET';

    my $ua = LWP::UserAgent->new( agent => $self->{agent} );
    my $response = $ua->request(
        HTTP::Request->new(
            $method, $url, $args{headers}, $args{content} || ''
        )
    );
    my @headers =
      map {
        my $k = $_;
        map { ( $k => $_ ) } $response->headers->header($_);
      } $response->headers->header_field_names;
    return ($response->code, \@headers, $response->content);
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
