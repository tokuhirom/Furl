package Furl::Response;
use strict;
use warnings;
use utf8;
use base qw/Class::Accessor::Fast/;
use Furl::Headers;

__PACKAGE__->mk_ro_accessors(qw/code msg headers content/);

sub new {
    my ($class, $code, $msg, $headers, $content) = @_;
    bless {
        code    => $code,
        msg     => $msg,
        headers => Furl::Headers->new($headers),
        content => $content
    }, $class;
}

sub content_length   { shift->content_length() }
sub content_type     { shift->content_type() }
sub content_encoding { shift->content_encoding() }
sub header           { shift->header(@_) }

sub as_http_response {
    my ($self) = @_;
    require HTTP::Response;
    HTTP::Response->new($self->code, $self->msg, $self->headers, $self->cotnent);
}

1;
__END__

=head1 SYNOPSIS

    my $res = Furl::Response->new($code, $msg, $headers, $content);

