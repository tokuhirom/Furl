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
        return wantarray ? @$val : $val->[0];
    }
}

sub push_header {
    my ($self, $key, @values) = @_;
    push @{$self->{lc $key}}, @values;
}

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

sub as_string {
    my $self = shift;
    my $ret = '';
    while (my ($k, $v) = each %$self) {
        for my $e (@$v) {
            $ret .= "$k: $v\015\012";
        }
    }
    return $ret;
}

sub as_http_headers {
    my ($self, $key) = @_;
    require HTTP::Headers;
    return HTTP::Headers->new([$self->flatten]);
}

# shortcut for popular headers.
sub expires           { shift->header( 'Expires'           => @_ ) }
sub last_modified     { shift->header( 'Last-Modified'     => @_ ) }
sub if_modified_since { shift->header( 'If-Modified-Since' => @_ ) }
sub content_type      { shift->header( 'Content-Type'      => @_ ) }
sub content_length    { shift->header( 'Content-Length'    => @_ ) }

1;
