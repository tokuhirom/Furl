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

=head1 SYNOPSIS

    use Furl;

    my $furl = Furl->new(
        agent   => 'MyGreatUA/2.0',
        timeout => 10,
    );

    my $res = $furl->get('http://example.com/');
    die $res->status_line unless $res->is_success;
    print $res->content;

    my $res = $furl->post(
        'http://example.com/', # URL
        [...],                 # headers
        [ foo => 'bar' ],      # form data (HashRef/FileHandle are also okay)
    );

    # Accept-Encoding is supported but optional
    $furl = Furl->new(
        headers => [ 'Accept-Encoding' => 'gzip' ],
    );
    my $body = $furl->get('http://example.com/some/compressed');

=head1 DESCRIPTION

Furl is yet another HTTP client library. LWP is the de facto standard HTTP
client for Perl5, but it is too slow for some critical jobs, and too complex
for weekend hacking. Furl resolves these issues. Enjoy it!

This library is an B<alpha> software. Any API may change without notice.

=head1 INTERFACE

=head2 Class Methods

=head3 C<< Furl->new(%args | \%args) :Furl >>

Creates and returns a new Furl client with I<%args>. Dies on errors.

I<%args> might be:

=over

=item agent :Str = "Furl/$VERSION"

=item timeout :Int = 10

=item max_redirects :Int = 7

=item proxy :Str

=item no_proxy :Str

=item headers :ArrayRef

=back

=head2 Instance Methods

=head3 C<< $furl->request(%args) :($code, $msg, \@headers, $body) >>

Sends an HTTP request to a specified URL and returns a instance of L<Furl::Response>.

I<%args> might be:

=over

=item scheme :Str = "http"

Protocol scheme. May be C<http> or C<https>.

=item host :Str

Server host to connect.

You must specify at least C<host> or C<url>.

=item port :Int = 80

Server port to connect. The default is 80 on C<< scheme => 'http' >>,
or 443 on C<< scheme => 'https' >>.

=item path_query :Str = "/"

Path and query to request.

=item url :Str

URL to request.

You can use C<url> instead of C<scheme>, C<host>, C<port> and C<path_query>.

=item headers :ArrayRef

HTTP request headers. e.g. C<< headers => [ 'Accept-Encoding' => 'gzip' ] >>.

=item content : Str | ArrayRef[Str] | HashRef[Str] | FileHandle

Content to request.

=back

You must encode all the queries or this method will die, saying
C<Wide character in ...>.

=head3 C<< $furl->get($url :Str, $headers :ArrayRef[Str] ) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->head($url :Str, $headers :ArrayRef[Str] ) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->post($url :Str, $headers :ArrayRef[Str], $content :Any) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->put($url :Str, $headers :ArrayRef[Str], $content :Any) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->delete($url :Str, $headers :ArrayRef[Str] ) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->request_with_http_request($req :HTTP::Request) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->env_proxy() >>

Loads proxy settings from C<< $ENV{HTTP_PROXY} >> and C<< $ENV{NO_PROXY} >>.

=head1 FAQ

=over 4

=item I need more speed.

See L<Furl::HTTP>, it is low level interface of L<Furl>. It is faster than Furl.pm since L<Furl::HTTP> does not create objects.

=back

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

Fuji, Goro (gfx)

=head1 THANKS TO

Kazuho Oku

mala

mattn

lestrrat

walf443


=head1 SEE ALSO

L<LWP>

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

