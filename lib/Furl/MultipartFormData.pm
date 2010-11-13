package Furl::MultipartFormData;
use strict;
use warnings;
use utf8;
use parent 'Exporter';
use Furl::Util;
use Furl::Headers;

our @EXPORT_OK = ('make_multipart_form_data');

my $CRLF = "\015\012";

# RFC1867
sub make_multipart_form_data {
    my ( $data, $boundary, $streaming ) = @_;
    my @data = ref($data) eq "HASH" ? %$data : @$data;    # copy
    my $fhparts;
    my @parts;
    my ( $k, $v );
    while ( ( $k, $v ) = splice( @data, 0, 2 ) ) {
        if ( !ref($v) ) {
            $k =~ s/([\\\"])/\\$1/g;    # escape quotes and backslashes
            push( @parts,
                qq(Content-Disposition: form-data; name="$k"$CRLF$CRLF$v) );
        }
        else {
            my ( $file, $usename, @headers ) = @$v;
            unless ( defined $usename ) {
                $usename = $file;
                $usename =~ s,.*/,, if defined($usename);
            }
            $k =~ s/([\\\"])/\\$1/g;
            my $disp = qq(form-data; name="$k");
            if ( defined($usename) and length($usename) ) {
                $usename =~ s/([\\\"])/\\$1/g;
                $disp .= qq(; filename="$usename");
            }
            my $content = "";
            my $h       = do{
                # make lower case the key.
                my @h;
                for (my $i=0; $i<@headers; $i+=2) {
                    push @h, lc($headers[$i]), $headers[$i+1];
                }
                Furl::Headers->new(\@h)
            };
            if ($file) {
                open( my $fh, "<", $file )
                  or Carp::croak("Can't open file $file: $!");
                binmode($fh);
                if ($streaming) {

                    # will read file later, close it now in order to
                    # not accumulate to many open file handles
                    close($fh);
                    $content = \$file;
                }
                else {
                    local ($/) = undef;    # slurp files
                    $content = <$fh>;
                    close($fh);
                }
                unless ( $h->header("Content-Type") ) {
                    require Plack::MIME;
                    $h->header('Content-Type' => Plack::MIME->mime_type( $file ) || 'application/octet-stream');
                }
            }
            if ( $h->header("Content-Disposition") ) {
                # just to get it sorted first
                $disp = $h->header("Content-Disposition");
                $h->remove_header("Content-Disposition");
            }
            if ( $h->header("Content") ) {
                $content = $h->header("Content");
                $h->remove_header("Content");
            }
            my $head = join( $CRLF,
                "Content-Disposition: $disp",
                $h->as_string($CRLF), "" );
            if ( ref $content ) {
                push( @parts, [ $head, $$content ] );
                $fhparts++;
            }
            else {
                push( @parts, $head . $content );
            }
        }
    }

    my $content;
    my $length = 0;
    if ($fhparts) {
        Furl::Util::requires('IO/Callback.pm', 'streaming upload for saving memory');
        $boundary = _make_boundary(10)    # hopefully enough randomness
          unless $boundary;

        # add the boundaries to the @parts array
        for ( 1 .. @parts - 1 ) {
            splice( @parts, $_ * 2 - 1, 0, "$CRLF--$boundary$CRLF" );
        }
        unshift( @parts, "--$boundary$CRLF" );
        push( @parts, "$CRLF--$boundary--$CRLF" );

        # See if we can generate Content-Length header
        for (@parts) {
            if ( ref $_ ) {
                my ( $head, $f ) = @$_;
                my $file_size;
                unless ( -f $f && ( $file_size = -s _ ) ) {

                    # The file is either a dynamic file like /dev/audio
                    # or perhaps a file in the /proc file system where
                    # stat may return a 0 size even though reading it
                    # will produce data.  So we cannot make
                    # a Content-Length header.
                    undef $length;
                    last;
                }
                $length += $file_size + length $head;
            }
            else {
                $length += length $_;
            }
        }

        # set up a closure that will return content piecemeal
        my $code = sub {
            for ( ; ; ) {
                unless (@parts) {
                    defined $length
                      && $length != 0
                      && Carp::croak(
"length of data sent did not match calculated Content-Length header.  Probably because uploaded file changed in size during transfer."
                      );
                    return;
                }
                my $p = shift @parts;
                unless ( ref $p ) {
                    $p .= shift @parts while @parts && !ref( $parts[0] );
                    defined $length && ( $length -= length $p );
                    return $p;
                }
                my ( $buf, $fh ) = @$p;
                unless ( ref($fh) ) {
                    my $file = $fh;
                    undef($fh);
                    open( $fh, "<", $file )
                      || Carp::croak("Can't open file $file: $!");
                    binmode($fh);
                }
                my $buflength = length $buf;
                my $n = read( $fh, $buf, 2048, $buflength );
                if ($n) {
                    $buflength += $n;
                    unshift( @parts, [ "", $fh ] );
                }
                else {
                    close($fh);
                }
                if ($buflength) {
                    defined $length && ( $length -= $buflength );
                    return $buf;
                }
            }
        };
        $content = IO::Callback->new('<', $code);

    }
    else {
        $boundary = _make_boundary() unless $boundary;

        my $bno = 0;
      CHECK_BOUNDARY:
        {
            for (@parts) {
                if ( index( $_, $boundary ) >= 0 ) {

                    # must have a better boundary
                    $boundary = _make_boundary( ++$bno );
                    redo CHECK_BOUNDARY;
                }
            }
            last;
        }
        $content =
            "--$boundary$CRLF"
          . join( "$CRLF--$boundary$CRLF", @parts )
          . "$CRLF--$boundary--$CRLF";
        $length = length($content);
    }

    return ($content, $boundary, $length);
}

sub _make_boundary {
    my $size = shift || return "xYzZY";
    require MIME::Base64; # MIME::Base64 was first released with perl v5.7.3
    my $b =
      MIME::Base64::encode( join( "", map chr( rand(256) ), 1 .. $size * 3 ),
        "" );
    $b =~ s/[\W]/X/g;    # ensure alnum only
    $b;
}

1;
__END__

=head1 NAME

Furl::MultipartFormData - multipart/form-data encoder for Furl

=head1 SYNOPSIS

    use Furl::HTTP;
    my ($content, $boundary, $length) = make_multipart_form_data(
        [name => 'john', file => ['image/foo.jpg']]
    );
    my ( $data, $boundary, $streaming ) = @_;

=head1 DESCRIPTION

This is a helper class. multipart/form-data encoder for Furl.

=head1 FEATURES

=head2 STREAMING UPLOAD

This feature requires L<IO::Callback>.

=head1 OPTIONAL DEPENDENCIES

=head2 IO::Callback

This module requires IO::Callback for streaming upload.

=head1 SEE ALSO

RFC1867

