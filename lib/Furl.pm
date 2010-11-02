package Furl;
use strict;
use warnings;
use utf8;
use Furl::HTTP;
use Furl::Response;
our $VERSION = '0.09';

use 5.008001;

sub new {
    my $class = shift;
    bless \(Furl::HTTP->new(header_format => Furl::HTTP::HEADERS_AS_HASHREF(), @_)), $class;
}

{
    no strict 'refs';
    for my $meth (qw/request get head post delete put request_with_http_request/) {
        *{__PACKAGE__ . '::' . $meth} = sub {
            my $self = shift;
            Furl::Response->new(${$self}->$meth(@_));
        }
    }
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

=head3 C<< $furl->request(%args) :Furl::Response >>

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

=head3 C<< $furl->request_with_http_request($req :HTTP::Request) >>

This is an easy-to-use alias to C<request()> with an instance of
C<HTTP::Request>.

=head3 C<< $furl->env_proxy() >>

Loads proxy settings from C<< $ENV{HTTP_PROXY} >> and C<< $ENV{NO_PROXY} >>.

=head1 FAQ

=over 4

=item I need more speed.

See L<Furl::HTTP>, which provides the low level interface of L<Furl>.
It is faster than C<Furl.pm> since L<Furl::HTTP> does not create response objects.

=item How do you use cookie_jar?

Furl does not directly support the cookie_jar option available in LWP. You can use L<HTTP::Cookies>, L<HTTP::Request>, L<HTTP::Response> like following.

    my $f = Furl->new();
    my $cookies = HTTP::Cookies->new();
    my $req = HTTP::Request->new(...);
    $cookies->add_cookie_header($req);
    my $res = H$f->request_with_http_request($req)->as_http_response;
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

L<Furl::HTTP>

L<Furl::Response>

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
