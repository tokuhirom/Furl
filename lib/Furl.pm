package Furl;
use strict;
use warnings;
use utf8;
use Furl::HTTP;
use Furl::Request;
use Furl::Response;
use Carp ();
our $VERSION = '3.08';

use 5.008001;

$Carp::Internal{+__PACKAGE__} = 1;

sub new {
    my $class = shift;
    bless \(Furl::HTTP->new(header_format => Furl::HTTP::HEADERS_AS_HASHREF(), @_)), $class;
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
    my ( $self, $url, $headers, $content ) = @_;
    $self->request(
        method  => 'DELETE',
        url     => $url,
        headers => $headers,
        content => $content
    );
}


sub agent {
    @_ == 2 ? ${$_[0]}->agent($_[1]) : ${$_[0]}->agent;
}

sub env_proxy {
    my $self = shift;
    $$self->env_proxy;
}

sub request {
    my $self = shift;

    my %args;
    if (@_ % 2 == 0) {
        %args = @_;
    } else {
        # convert HTTP::Request to hash for Furl::HTTP.

        my $req = shift;
        %args = @_;
        my $req_headers= $req->headers;
        $req_headers->remove_header('Host'); # suppress duplicate Host header
        my $headers = +[
            map {
                my $k = $_;
                map { ( $k => $_ ) } $req_headers->header($_);
            } $req_headers->header_field_names
        ];

        $args{url}     = $req->uri;
        $args{method}  = $req->method;
        $args{content} = $req->content;
        $args{headers} = $headers;
    }

    my (
        $res_minor_version,
        $res_status,
        $res_msg,
        $res_headers,
        $res_content,
        $captured_req_headers,
        $captured_req_content,
        $captured_res_headers,
        $captured_res_content,
        $request_info,
        ) = ${$self}->request(%args);

    my $res = Furl::Response->new($res_minor_version, $res_status, $res_msg, $res_headers, $res_content);
    $res->set_request_info(\%args, $captured_req_headers, $captured_req_content);

    return $res;
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
client for Perl 5, but it is too slow for some critical jobs, and too complex
for weekend hacking. Furl resolves these issues. Enjoy it!

=head1 INTERFACE

=head2 Class Methods

=head3 C<< Furl->new(%args | \%args) :Furl >>

Creates and returns a new Furl client with I<%args>. Dies on errors.

I<%args> might be:

=over

=item agent :Str = "Furl/$VERSION"

=item timeout :Int = 10

=item max_redirects :Int = 7

=item capture_request :Bool = false

If this parameter is true, L<Furl::HTTP> captures raw request string.
You can get it by C<< $res->captured_req_headers >> and C<< $res->captured_req_content >>.

=item proxy :Str

=item no_proxy :Str

=item headers :ArrayRef

=item cookie_jar :Object

(EXPERIMENTAL)

An instance of HTTP::CookieJar or equivalent class that supports the add and cookie_header methods

=back

=head2 Instance Methods

=head3 C<< $furl->request([$request,] %args) :Furl::Response >>

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

If the number of arguments is an odd number, this method assumes that the
first argument is an instance of C<HTTP::Request>. Remaining arguments
can be any of the previously describe values (but currently there's no
way to really utilize them, so don't use it)

    my $req = HTTP::Request->new(...);
    my $res = $furl->request($req);

You can also specify an object other than HTTP::Request (e.g. Furl::Request),
but the object must implement the following methods:

=over 4

=item uri

=item method

=item content

=item headers

=back

These must return the same type of values as their counterparts in
C<HTTP::Request>.

You must encode all the queries or this method will die, saying
C<Wide character in ...>.

=head3 C<< $furl->get($url :Str, $headers :ArrayRef[Str] ) >>

This is an easy-to-use alias to C<request()>, sending the C<GET> method.

=head3 C<< $furl->head($url :Str, $headers :ArrayRef[Str] ) >>

This is an easy-to-use alias to C<request()>, sending the C<HEAD> method.

=head3 C<< $furl->post($url :Str, $headers :ArrayRef[Str], $content :Any) >>

This is an easy-to-use alias to C<request()>, sending the C<POST> method.

=head3 C<< $furl->put($url :Str, $headers :ArrayRef[Str], $content :Any) >>

This is an easy-to-use alias to C<request()>, sending the C<PUT> method.

=head3 C<< $furl->delete($url :Str, $headers :ArrayRef[Str] ) >>

This is an easy-to-use alias to C<request()>, sending the C<DELETE> method.

=head3 C<< $furl->env_proxy() >>

Loads proxy settings from C<< $ENV{HTTP_PROXY} >> and C<< $ENV{NO_PROXY} >>.

=head1 FAQ

=over 4

=item Does Furl depends on XS modules?

No. Although some optional features require XS modules, basic features are
available without XS modules.

Note that Furl requires HTTP::Parser::XS, which seems an XS module
but includes a pure Perl backend, HTTP::Parser::XS::PP.

=item I need more speed.

See L<Furl::HTTP>, which provides the low level interface of L<Furl>.
It is faster than C<Furl.pm> since L<Furl::HTTP> does not create response objects.

=item How do you use cookie_jar?

Furl does not directly support the cookie_jar option available in LWP. You can use L<HTTP::Cookies>, L<HTTP::Request>, L<HTTP::Response> like following.

    my $f = Furl->new();
    my $cookies = HTTP::Cookies->new();
    my $req = HTTP::Request->new(...);
    $cookies->add_cookie_header($req);
    my $res = $f->request($req)->as_http_response;
    $res->request($req);
    $cookies->extract_cookies($res);
    # and use $res.

=item How do you limit the response content length?

You can limit the content length by callback function.

    my $f = Furl->new();
    my $content = '';
    my $limit = 1_000_000;
    my %special_headers = ('content-length' => undef);
    my $res = $f->request(
        method          => 'GET',
        url             => $url,
        special_headers => \%special_headers,
        write_code      => sub {
            my ( $status, $msg, $headers, $buf ) = @_;
            if (($special_headers{'content-length'}||0) > $limit || length($content) > $limit) {
                die "over limit: $limit";
            }
            $content .= $buf;
        }
    );

=item How do you display the progress bar?

    my $bar = Term::ProgressBar->new({count => 1024, ETA => 'linear'});
    $bar->minor(0);
    $bar->max_update_rate(1);

    my $f = Furl->new();
    my $content = '';
    my %special_headers = ('content-length' => undef);;
    my $did_set_target = 0;
    my $received_size = 0;
    my $next_update  = 0;
    $f->request(
        method          => 'GET',
        url             => $url,
        special_headers => \%special_headers,
        write_code      => sub {
            my ( $status, $msg, $headers, $buf ) = @_;
            unless ($did_set_target) {
                if ( my $cl = $special_headers{'content-length'} ) {
                    $bar->target($cl);
                    $did_set_target++;
                }
                else {
                    $bar->target( $received_size + 2 * length($buf) );
                }
            }
            $received_size += length($buf);
            $content .= $buf;
            $next_update = $bar->update($received_size)
            if $received_size >= $next_update;
        }
    );

=item HTTPS requests claims warnings!

When you make https requests, IO::Socket::SSL may complain about it like:

    *******************************************************************
     Using the default of SSL_verify_mode of SSL_VERIFY_NONE for client
     is depreciated! Please set SSL_verify_mode to SSL_VERIFY_PEER
     together with SSL_ca_file|SSL_ca_path for verification.
     If you really don't want to verify the certificate and keep the
     connection open to Man-In-The-Middle attacks please set
     SSL_verify_mode explicitly to SSL_VERIFY_NONE in your application.
    *******************************************************************

You should set C<SSL_verify_mode> explicitly with Furl's C<ssl_opts>.

    use IO::Socket::SSL;

    my $ua = Furl->new(
        ssl_opts => {
            SSL_verify_mode => SSL_VERIFY_PEER(),
        },
    );

See L<IO::Socket::SSL> for details.

=back

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom@gmail.comE<gt>

Fuji, Goro (gfx)

=head1 THANKS TO

Kazuho Oku

mala

mattn

lestrrat

walf443

lestrrat

audreyt

=head1 SEE ALSO

L<LWP>

L<IO::Socket::SSL>

L<Furl::HTTP>

L<Furl::Response>

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
