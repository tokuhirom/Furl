package Furl::KeepAlive;
use strict;
use warnings;
use Furl;
use LWP::UserAgent;
use WWW::Curl::Easy;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;

    bless {
        agent => __PACKAGE__ . '/' . $Furl::VERSION,
        port  => 80,
        timeout => 10,
        keepalive_timeout => 300,
        %args,
    }, $class;
}

sub request {
    my $self = shift;
    my %args = @_==1 ? %{$_[0]} : @_;

    my $path = $args{path} || '/';
    my $url = "http://$self->{host}:$self->{port}$path";

    my $method = $args{method} || 'GET';

    my $curl = ($self->{ua} ||= WWW::Curl::Easy->new());
    $curl->setopt(CURLOPT_URL, $url);
    open my $fh, '>', \my $content;
    $curl->setopt(CURLOPT_WRITEDATA, $fh);
    $curl->setopt(CURLOPT_USERAGENT, $self->{agent});
    $curl->setopt(CURLOPT_TIMEOUT, $self->{timeout});
    $curl->setopt( CURLOPT_HTTPHEADER,
        [
            (
                map { +"$_ : $self->{headers}->{$_}\015\012" }
                  @{ $self->{headers} }
            ),
            "Connection: Keep-Alive",
            "Keep-Alive: $self->{keepalive_timeout}",
            "\015\012",
        ]
    );
    $curl->setopt(CURLOPT_CUSTOMREQUEST, $method);
    $curl->setopt(CURLOPT_POSTFIELDS, $args{content} || '');
    $curl->setopt(CURLOPT_HEADER, 0);
    my @headers;
    $curl->setopt(CURLOPT_HEADERFUNCTION, sub {
        if (my ($k, $v) = ($_[0] =~ /^(.+)\s*:\s*(.+)\015\012$/)) {
            push @headers, $k, $v;
        }
        return length($_[0]);
    });
    my $retcode = $curl->perform();
    if ($retcode == 0) {
        my $code = $curl->getinfo(CURLINFO_HTTP_CODE);
        return ($code, \@headers, $content);
    } else {
        return (500, [], $curl->strerror($retcode));
    }
}

1;
__END__

=encoding utf8

=head1 NAME

Furl::KeepAlive -

=head1 SYNOPSIS

    use Furl::KeepAlive;

    my $furl = Furl::KeepAlive->new(agent => ..., port => 80, host => 'example.com');
    my ($code, $headers, $body) = $furl->request(
        method => 'GET',
        path   => '/'
    );
    # or
    my ($code, $headers, $body) = $furl->request(
        method => 'GET',
        path   => '/'
        save_to_tmpfile => 1,
    );

=head1 DESCRIPTION

Furl::KeepAlive is yet another http client library.

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
