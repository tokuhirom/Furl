package Furl;
use strict;
use warnings;
use utf8;
use base qw/Furl::HTTP/;
use Furl::Response;
our $VERSION = '0.04';

sub new {
    my $class = shift;
    return $class->SUPER::new( header_format => Furl::HTTP::HEADERS_AS_HASHREF(),
        @_ );
}

sub request {
    my $self = shift;
    my @res = $self->SUPER::request(@_);
    if(@res == 1) {
        # the response is already Furl::Response
        # because of retrying requests (e.g. by redirect)
        return $res[0];
    }
    else {
        # the response is that of Furl::HTTP->request
        return Furl::Response->new( @res );
    }
}

sub get {
    my ( $self, $url, $headers ) = @_;
    $self->request(
        method  => 'GET',
        url     => $url,
        headers => $headers
    );
}

sub head {
    my ( $self, $url, $headers ) = @_;
    $self->request(
        method  => 'HEAD',
        url     => $url,
        headers => $headers
    );
}

sub post {
    my ( $self, $url, $headers, $content ) = @_;
    $self->request(
        method  => 'POST',
        url     => $url,
        headers => $headers,
        content => $content
    );
}

sub put {
    my ( $self, $url, $headers, $content ) = @_;
    $self->request(
        method  => 'PUT',
        url     => $url,
        headers => $headers,
        content => $content
    );
}

sub delete {
    my ( $self, $url, $headers ) = @_;
    $self->request(
        method  => 'DELETE',
        url     => $url,
        headers => $headers
    );
}

sub request_with_http_request {
    my ($self, $req, %args) = @_;
    my $headers = +[
        map {
            my $k = $_;
            map { ( $k => $_ ) } $req->headers->header($_);
          } $req->headers->header_field_names
    ];
    $self->request(
        url     => $req->uri,
        method  => $req->method,
        content => $req->content,
        headers => $headers,
        %args
    );
}

1;
__END__

=encoding utf8

=head1 NAME

Furl - Lightning-fast URL fetcher
