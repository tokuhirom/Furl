package Furl::ZlibStream;
# internal class.
use strict;
use warnings;
use overload '.=' => 'append', fallback => 1;
use Carp ();
use Compress::Raw::Zlib qw(Z_OK Z_STREAM_END);

# Compressed input is inflated in slices of this size. DEFLATE expands at
# most ~1032:1, so one inflate() call yields at most a few MB, and the
# size limit is checked before a single call can produce an unbounded
# amount of output (a chunked response can hand us one huge chunk).
my $SLICE = 4096;

sub new {
    my ( $class, $buffer, $max_size ) = @_;

    my ( $zlib, $status ) = Compress::Raw::Zlib::Inflate->new(
        -WindowBits => Compress::Raw::Zlib::WANT_GZIP_OR_ZLIB(), );
    $status == Z_OK
        or Carp::croak("Cannot initialize zlib: $status");

    bless {
        buffer   => $buffer,
        zlib     => $zlib,
        max_size => $max_size,
        size     => 0,
    }, $class;
}

sub append {
    my ( $self, $partial ) = @_;

    for ( my $offset = 0; $offset < length $partial; $offset += $SLICE ) {
        # inflate() consumes its input, so hand it a copy of the slice.
        my $input = substr( $partial, $offset, $SLICE );
        my $status = $self->{zlib}->inflate( $input, \my $deflated );
        ($status == Z_OK or $status == Z_STREAM_END)
            or Carp::croak("Uncompress error: $status");

        $self->{size} += length $deflated;
        if ( $self->{max_size} && $self->{size} > $self->{max_size} ) {
            Carp::croak( "Decompressed response body exceeds "
                    . "max_decompressed_size ($self->{max_size} bytes)" );
        }
        $self->{buffer} .= $deflated;

        last if $status == Z_STREAM_END;
    }

    return $self;
}

sub get_response_string { ref $_[0]->{buffer} ? undef : $_[0]->{buffer} }

1;
