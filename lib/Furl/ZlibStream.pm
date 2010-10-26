package Furl::ZlibStream;
# internal class.
use strict;
use warnings;
use overload '.=' => 'append', fallback => 1;
use Carp ();
use Compress::Raw::Zlib qw(Z_OK Z_STREAM_END);

sub new {
    my ( $class, $buffer ) = @_;

    my ( $zlib, $status ) = Compress::Raw::Zlib::Inflate->new(
        -WindowBits => Compress::Raw::Zlib::WANT_GZIP_OR_ZLIB(), );
    $status == Z_OK
        or Carp::croak("Cannot initialize zlib: $status");

    bless { buffer => $buffer, zlib => $zlib }, $class;
}

sub append {
    my ( $self, $partial ) = @_;

    my $status = $self->{zlib}->inflate( $partial, \my $deflated );
    ($status == Z_OK or $status == Z_STREAM_END)
        or Carp::croak("Uncompress error: $status");
    $self->{buffer} .= $deflated;

    return $self;
}

sub get_response_string { ref $_[0]->{buffer} ? undef : $_[0]->{buffer} }

1;
