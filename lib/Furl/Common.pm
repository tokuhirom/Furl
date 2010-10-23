package Furl::Common;
use strict;
use warnings;
use Furl;

sub new {
    my $class = shift;
    my $furl = Furl->new(@_);
    bless {furl => $furl}, $clas;
}

sub get {
    my ($self, $url, $headers) = @_;
    $self->{furl}->request(url => $url, headers => $headers);
}

sub post {
    my ($self, $url, $headers, $content) = @_;
    if (ref $content && ref $content eq 'ARRAY') {
        my @p = @$content;
        my @params;
        while (my ($k, $v) = splice @p, 0, 2) {
            push @params, URI::Escape::uri_escape($k)
            . '=' .
            URI::Escape::uri_escape($v)
        }
        $content = join("&", @params);
    }

    $self->{furl}->request(url => $url, headers => $headers, content => $content);
}

1;
__END__


    Furl::Easy or Furl::Common or Furl::REST or something.
    18:53 tokuhirom: ->put($url, \@headers, $content)
    18:53 tokuhirom: ->head($url, \@headers)
    18:53 tokuhirom: ->get($url, \@headers)
    18:53 tokuhirom: ->delete($url, \@headers)
    18:53 tokuhirom: ->post($url, \@headers, \@content)
    18:53 tokuhirom: ->post($url, \@headers, $content)

