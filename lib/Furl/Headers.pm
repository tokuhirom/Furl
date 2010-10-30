package Furl::Headers;
use strict;
use warnings;
use utf8;

sub new {
    my ($class, $headers) = @_; # $headers is HashRef or ArrayRef
    if (ref $headers eq 'ARRAY') {
        my @h = @$headers; # copy
        $headers = {};
        while (my ($k, $v) = splice @h, 0, 2) {
            push @{$headers->{$k}}, $v;
        }
    }
    bless $headers, $class;
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

sub push_header {
    my ($self, $key) = (shift, shift);
    push @{$self->{lc $key}}, @_;
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

sub keys {
    my $self = shift;
    keys %$self;
}
sub header_field_names { shift->keys }

sub as_string {
    my $self = shift;
    my $ret = '';
    while (my ($k, $v) = each %$self) {
        for my $e (@$v) {
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

1;
