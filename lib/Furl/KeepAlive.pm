package Furl::KeepAlive;
use strict;
use warnings;
use Furl;
use LWP::UserAgent;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;

    bless {
        agent => __PACKAGE__ . '/' . $Furl::VERSION,
        port  => 80,
        %args,
    }, $class;
}

sub request {
    my $self = shift;
    my %args = @_==1 ? %{$_[0]} : @_;

    my $path = $args{path} || '/';
    my $url = "http://$self->{host}:$self->{port}$path";

    my $method = $args{method} || 'GET';

    $self->{ua} ||=
      LWP::UserAgent->new( agent => $self->{agent}, keep_alive => 1 );
    my $response = $self->{ua}->request(
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

Furl::KeepAlive -

=head1 SYNOPSIS

    use Furl::KeepAlive;

    my $furl = Furl::KeepAlive->new(agent => ..., port => 80, host => 'example.com');
    my ($code, $headers, $body) = $furl->request(
        method => 'GET',
        path   => '/'
    );
    # or
    my ($code, $headers, $body) = $furl->request(
        method => 'GET',
        path   => '/'
        save_to_tmpfile => 1,
    );

=head1 DESCRIPTION

Furl::KeepAlive is yet another http client library.

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
