package Furl::Headers;
use strict;
use warnings;
use utf8;
use Carp ();

sub new {
    my ($class, $headers) = @_; # $headers is HashRef or ArrayRef
    my $self = {};
    if (ref $headers eq 'ARRAY') {
        my @h = @$headers; # copy
        while (my ($k, $v) = splice @h, 0, 2) {
            push @{$self->{lc $k}}, $v;
        }
    }
    elsif(ref $headers eq 'HASH') {
        while (my ($k, $v) = each %$headers) {
            push @{$self->{$k}}, ref($v) eq 'ARRAY' ? @$v : $v;
        }
    }
    else {
        Carp::confess($class . ': $headers must be an ARRAY or HASH reference');
    }

    bless $self, $class;
}

sub header {
    my ($self, $key, $new) = @_;
    if ($new) { # setter
        $new = [$new] unless ref $new;
        $self->{lc $key} = $new;
        return;
    } else {
        my $val = $self->{lc $key};
        return unless $val;
        return wantarray ? @$val : join(", ", @$val);
    }
}

sub remove_header {
    my ($self, $key) = @_;
    delete $self->{lc $key};
}

sub flatten {
    my $self = shift;
    my @ret;
    while (my ($k, $v) = each %$self) {
        for my $e (@$v) {
            push @ret, $k, $e;
        }
    }
    return @ret;
}

sub keys :method {
    my $self = shift;
    keys %$self;
}
sub header_field_names { shift->keys }

sub as_string {
    my $self = shift;
    my $ret = '';
    for my $k (sort keys %$self) {
        for my $e (@{$self->{$k}}) {
            $ret .= "$k: $e\015\012";
        }
    }
    return $ret;
}

sub as_http_headers {
    my ($self, $key) = @_;
    require HTTP::Headers;
    return HTTP::Headers->new($self->flatten);
}

# shortcut for popular headers.
sub referer           { [ shift->header( 'Referer'           => @_ ) ]->[0] }
sub expires           { [ shift->header( 'Expires'           => @_ ) ]->[0] }
sub last_modified     { [ shift->header( 'Last-Modified'     => @_ ) ]->[0] }
sub if_modified_since { [ shift->header( 'If-Modified-Since' => @_ ) ]->[0] }
sub content_type      { [ shift->header( 'Content-Type'      => @_ ) ]->[0] }
sub content_length    { [ shift->header( 'Content-Length'    => @_ ) ]->[0] }
sub content_encoding  { [ shift->header( 'Content-Encoding'  => @_ ) ]->[0] }

sub clone {
    require Storable;
    Storable::dclone($_[0]);
}

1;
__END__

=head1 NAME

Furl::Headers - HTTP Headers object

=head1 SYNOPSIS

=head1 CONSTRUCTOR

=over 4

=item my $headers = Furl::Headers->new(\%headers);

The constructor takes one argument. It is a hashref.
Every key of hashref must be lower-cased.

The format of the argument is like following:

    +{
        'content-length' => [30],
        'set-cookies'    => ['auth_token=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT', '_twitter_sess=JKLJBNBLKSFJBLKSJBLKSJLKJFLSDJFjkDKFUFIOSDUFSDVjOTUzNzUwNTE2%250AZWFiMWRiNDZhMDcwOWEwMWQ5IgpmbGFzaElDOidBY3Rpb25Db250cm9sbGVy%250AOjpGbGFzaDo6Rmxhc2hIYXNoewAGOgpAdXNlZHsA--d9ce07496a22525bc178jlkhafklsdjflajfl411; domain=.twitter.com; path=/'],
    }

=back

=head1 INSTANCE METHODS

=over 4

=item my @values = $headers->header($key);

Get the header value in array.

=item my $values_joined = $headers->header($key);

Get the header value in scalar. This is not a first value of header. This is same as:

    my $values = join(", ", $headers->header($key))

=item $headers->header($key, $val);

=item $headers->header($key, \@val);

Set the new value of headers.

=item $headers->remove_header($key);

Delete key from headers.

=item my @h = $headers->flatten();

Gets pairs of keys and values.

=item my @keys = $headers->keys();

=item my @keys = $headers->header_field_names();

Returns keys of headers in array. The return value do not contains duplicated value.

=item my $str = $headers->as_string();

Return the header fields as a formatted MIME header.

=item my $val = $headers->referer()

=item my $val = $headers->expires()

=item my $val = $headers->last_modified()

=item my $val = $headers->if_modified_since()

=item my $val = $headers->content_type()

=item my $val = $headers->content_length()

=item my $val = $headers->content_encoding()

These methods are shortcut for popular headers.

=item $headers->clone();

Returns a copy of this "Furl::Headers" object.

=back

=head1 SEE ALSO

L<HTTP::Headers>

=cut
