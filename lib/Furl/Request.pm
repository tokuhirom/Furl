package Furl::Request;

use strict;
use warnings;
use utf8;
use Furl::Headers;

sub new {
    my ($class, $minor_version, $method, $uri, $headers, $content) = @_;

    bless +{
        minor_version => $minor_version,
        method        => $method,
        uri           => $uri,
        headers       => Furl::Headers->new($headers),
        content       => $content,
    } => $class;
}

# accessors
sub method  { shift->{method} }
sub uri     { shift->{uri} }
sub headers { shift->{headers} }
sub content { shift->{content} }

# alias
sub body { shift->content }

# shorthand
sub content_length { shift->headers->content_length }
sub content_type   { shift->headers->content_type }
sub header         { shift->headers->header(@_) }

sub protocol {
    my $self = shift;
    sprintf 'HTTP/1.%d' => $self->{minor_version};
}

sub request_line {
    my $self = shift;
    sprintf '%s %s %s' => $self->method, $self->uri, $self->protocol;
}

sub as_http_request {
    my $self = shift;

    require HTTP::Request;
    my $req = HTTP::Request->new(
        $self->method,
        $self->uri,
        [ $self->headers->flatten ],
        $self->content,
    );

    $req->protocol($self->protocol);
    return $req;
}

sub as_hashref {
    my $self = shift;

    return +{
        method   => $self->method,
        uri      => $self->uri,
        protocol => $self->protocol,
        headers  => [ $self->headers->flatten ],
        content  => $self->content,
    };
}

1;
__END__

=head1 NAME

Furl::Request - Request object for Furl

=head1 SYNOPSIS

    my $req = Furl::Request->new($minor_version, $method, $uri, $headers, $content);
    print $req->request_line, "\n";

    my $http_req = $req->as_http_request;
    my $req_hash = $req->as_hashref;

=head1 DESCRIPTION

This is a HTTP request object in Furl.

=head1 CONSTRUCTOR

    my $req = Furl::Request->new($minor_version, $method, $uri, \%headers, $content);

=head1 INSTANCE METHODS

=over 4

=item $req->method

Returns HTTP request method

=item $req->uri

Returns request uri

=item $req->headers

Returns instance of L<Furl::Headers>

=item $req->content

=item $req->body

Returns request body in scalar.

=item $req->content_length

=item $req->content_type

=item $req->header

Shorthand to access L<Furl::Headers>.

=item $req->protocol

    print $req->protocol; #=> "HTTP/1.1"

Returns HTTP protocol in string.

=item $req->as_http_request

Make instance of L<HTTP::Request> from L<Furl::Request>.

=item $req->as_hashref

Convert request object to HashRef.

Format is following:

    method: Strt
    uri: Str
    protocol: Str
    headers: ArrayRef[Str]
    content: Str

=item $req->request_line

    print $req->request_line; #=> "GET / HTTP/1.1"

Returns HTTP request line.

=back
