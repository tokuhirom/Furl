package Furl::KeepAlive;
use strict;
use warnings;
use Furl;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;

    my $agent = __PACKAGE__ . '/' . $Furl::VERSION;
    my $timeout = $args{timeout} || 10;
    bless {
        port              => 80,
        curl              => Furl::_new_curl($agent, $timeout),
        parse_header      => 1,
        %args,
    }, $class;
}

sub request {
    my $self = shift;
    my %args = @_==1 ? %{$_[0]} : @_;

    my $path = $args{path} || '/';
    my $url = "http://$self->{host}:$self->{port}$path";

    my $method = $args{method} || 'GET';
    my $content = $args{content} || '';
    my @headers = @{$args{headers} || []};

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
