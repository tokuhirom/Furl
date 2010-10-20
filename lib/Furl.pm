package Furl;
use strict;
use warnings;
use 5.00800;
our $VERSION = '0.01';

use Carp ();
use POSIX qw(:errno_h);
use XSLoader;
use Socket qw/inet_aton PF_INET SOCK_STREAM pack_sockaddr_in/;

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
            my $url = $args{url};
            if (ref $url) {
                ($url->host, $url->port, $url->path_query);
            } else {
                $url =~ s!^http://!!;
                my ($hostport, $path) = split m{/}, $url, 2;
                my ($host, $port) = split /:/, $hostport;
                ($host, $port || 80, $path || '/');
            }
        } else {
            ($args{host}, $args{port} || 80, $args{path_query} || '/');
        }
    };
    my $content = $args{content};
    my @headers = @{$args{headers} || []};

    my $method = $args{method} || 'GET';

    local $SIG{PIPE} = 'IGNORE';
    my $err = sub { delete $self->{sock_cache}; return @_ };
    my $sock;
    if ($self->{sock_cache} && $self->{sock_cache}->{host} eq $host && $self->{sock_cache}->{port}  eq $port) {
        $sock = $self->{sock_cache}->{sock};
    } else {
        my $iaddr = inet_aton($host) or die "cannot detect host name: $host, $!";
        my $sock_addr = pack_sockaddr_in($port, $iaddr);
        socket($sock, PF_INET, SOCK_STREAM, 0) or die "Cannot create socket: $!";
        connect($sock, $sock_addr) or die "cannot connect to $host, $port: $!";
        {
            # no buffering
            my $orig = select();
            select($sock); $|=1; 
            select($orig);
        }
    }
    {
        my $p = "$method $path_query HTTP/1.1\015\012Host: $host:$port\015\012Connection: Keep-Alive\015\012";
        for my $h (@headers) {
            $p .= $h . "\015\012";
        }
        $p .= "\015\012";
        defined(syswrite($sock, $p, length($p))) or return $err->(500, [], ['Broken Pipe']);
        if ($content) {
            defined(syswrite($sock, $content, length($content))) or die $!;
        }
    }
    my $buf = '';
    my $last_len = 0;
    my $status;
    my $res_headers;
    my $res_content;
    my $res_connection;
    my $res_minor_version;
    my $res_content_length;
  LOOP: while (1) {
        my $read = sysread($sock, $buf, $self->{bufsize}, length($buf) );
        if (not defined $read || $read < 0) {
            die "error while reading from socket: $!";
        } elsif ( $read == 0 ) {    # eof
            return $err->(500, [], "Unexpected EOF: $!");
        }
        else {
            ( $res_minor_version, $status, $res_content_length, $res_connection, $res_headers, my $ret ) =
              parse_http_response( $buf, $last_len );
            if ( $ret == -1 ) {
                return $err->(500, [], ["invalid HTTP response"]);
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
    my $sent_length = length($res_content);
    READ_LOOP: while ($res_content_length == -1 || $res_content_length != $sent_length) {
        my $bufsize = $self->{bufsize};
        if ($res_content_length != -1 && $res_content_length - $sent_length < $bufsize) {
            $bufsize = $res_content_length - $sent_length;
        }
        # TODO: save to fh
        my $readed = sysread($sock, my $buf, $bufsize);
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
    if ($res_content_length == -1 || $res_minor_version == 0 || lc($res_connection) eq 'close') {
        delete $self->{sock_cache};
        undef $sock;
    } else {
        $self->{sock_cache}->{sock} = $sock;
        $self->{sock_cache}->{host} = $host;
        $self->{sock_cache}->{port} = $port;
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

=head1 TODO

    - follow redirect
    - LWP compat interface: ->get, ->post
        ->get($url)
    - form serializer
        seraizlie_x_www_url_encoded(foo => bar, baz => 1);
    - timeout
    - idn support(with Net-IDN-Encode?)
    - proxy support
    - env_proxy support
    - cookie_jar support
    - timeout support

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
