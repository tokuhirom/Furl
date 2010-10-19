package Furl;
use strict;
use warnings;
use 5.00800;
our $VERSION = '0.01';

use Carp ();
use IO::Socket::INET;
use POSIX qw(:errno_h);
use XSLoader;
use URI;

XSLoader::load __PACKAGE__, $VERSION;

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    my $agent = __PACKAGE__ . '/' . $VERSION;
    my $timeout = $args{timeout} || 10;
    bless {
        parse_header => 1,
        timeout => $timeout,
        bufsize => 1024*1024,
        %args
    }, $class;
}

sub request {
    my $self = shift;
    my %args = @_;

    my ($host, $port, $path_query) = do {
        if ($args{url}) {
            # TODO: parse by regexp if it's not object.
            my $url = $args{url};
               $url = URI->new($url) unless ref $url;
            ($url->host, $url->port, $url->path_query);
        } else {
            ($args{host}, $args{port} || 80, $args{path_query} || '/');
        }
    };
    my $content = $args{content};
    my @headers = @{$args{headers} || []};

    my $method = $args{method} || 'GET';

    local $SIG{PIPE} = 'IGNORE';
    my $sock = IO::Socket::INET->new(
        PeerHost => $host,
        PeerPort => $port,
        Timeout  => $self->{timeout},
    ) or Carp::croak("cannot connect to $host:$port, $!");
    {
        my $p = "$method $path_query HTTP/1.0\015\012";
        $p .= join("\015\012", @headers);
        $p .= "\015\012\015\012";
        defined(syswrite($sock, $p, length($p))) or die $!;
        if ($content) {
            defined(syswrite($sock, $content, length($content))) or die $!;
        }
    }
    my $buf = '';
    my $last_len = 0;
    my $status;
    my $res_headers;
    my $res_content;
  LOOP: while (1) {
        my $read = read($sock, $buf, $self->{bufsize}, length($buf) );
        if (not defined $read || $read < 0) {
            die "error while reading from socket: $!";
        } elsif ( $read == 0 ) {    # eof
            die "eof";
        }
        else {
            ( $status, $res_headers, my $ret ) =
              parse_http_response( $buf, $last_len );
            if ( $ret == -1 ) {
                die "invalid HTTP response";
            }
            elsif ( $ret == -2 ) {
                # partial response
                $last_len = length($buf);
                next LOOP;
            }
            else {
                # succeeded
                $res_content = substr( $buf, $ret );
                last LOOP;
            }
        }
    }
    my $content_length = sub {
        for (my $i=0; $i<@$res_headers; $i+=2) {
            return $res_headers->[$i+1] if lc($res_headers->[$i]) eq 'content-length';
        }
        return -1;
    }->();
    my $sent_length = 0;
    READ_LOOP: while ($content_length == -1 || $content_length != $sent_length) {
        my $bufsize = $self->{bufsize};
        if ($content_length != -1 && $content_length - $sent_length < $bufsize) {
            $bufsize = $content_length - $sent_length;
        }
        # TODO: save to fh
        my $readed = read($sock, my $buf, $bufsize);
        if (not defined $readed || $readed < 0 ) {
            next READ_LOOP if $? == EAGAIN;
        }
        if ($readed == 0) {
            # eof
            last READ_LOOP;
        }
        $res_content .= substr($buf, 0, $readed);
        $sent_length += $readed;
    }
    return ($status, $res_headers, $res_content);
}

1;
__END__

=encoding utf8

=head1 NAME

Furl -

=head1 SYNOPSIS

    use Furl;

    my $furl = Furl->new(agent => ...);
    my ($code, $headers, $body) = $furl->request(
        method => 'GET',
        host   => 'example.com',
        port   => 80,
        path   => '/'
    );
    # or
    my ($code, $headers, $body) = $furl->request(
        method => 'GET',
        host   => 'example.com',
        port   => 80,
        path   => '/'
        save_to_tmpfile => 1,
    );

=head1 DESCRIPTION

Furl is yet another http client library.

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
