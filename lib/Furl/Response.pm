package Furl::Response;
use strict;
use warnings;
use utf8;
use base qw/Class::Accessor::Fast/;
use Furl::Headers;

__PACKAGE__->mk_ro_accessors(qw/code message headers content/);

sub new {
    my ($class, $minor_version, $code, $message, $headers, $content) = @_;
    bless {
        minor_version => $minor_version,
        code    => $code,
        message => $message,
        headers => Furl::Headers->new($headers),
        content => $content
    }, $class;
}

# alias
sub status { shift->code() }
sub body   { shift->content() }

# shorthand
sub content_length   { shift->headers->content_length() }
sub content_type     { shift->headers->content_type() }
sub content_encoding { shift->headers->content_encoding() }
sub header           { shift->headers->header(@_) }

sub protocol { "HTTP/1." . $_[0]->{minor_version} }

sub as_http_response {
    my ($self) = @_;
    require HTTP::Response;
    my $res = HTTP::Response->new( $self->code, $self->message,
        [ $self->headers->flatten ],
        $self->content );
    $res->protocol($self->protocol);
    return $res;
}

sub is_success { substr( $_[0]->code, 0, 1 ) eq '2' }
sub status_line { $_[0]->code . ' ' . $_[0]->message }

1;
__END__

=head1 SYNOPSIS

    my $res = Furl::Response->new($code, $message, $headers, $content);

