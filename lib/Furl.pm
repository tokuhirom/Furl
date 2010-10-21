package Furl;
use strict;
use warnings;
use 5.00800;
our $VERSION = '0.01';

use Carp ();
use Errno qw(EAGAIN EINTR EWOULDBLOCK);
use XSLoader;
use Socket qw/inet_aton PF_INET SOCK_STREAM pack_sockaddr_in IPPROTO_TCP TCP_NODELAY/;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use URI;

XSLoader::load __PACKAGE__, $VERSION;

my $HTTP_TOKEN = '[^\x00-\x31\x7F]+';
my $HTTP_QUOTED_STRING = q{"([^"]+|\\.)*"};

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;

    my $agent = $args{agent} || __PACKAGE__ . '/' . $VERSION;
    bless {
        timeout       => 10,
        max_redirects => 7,
        bufsize       => 10*1024, # no mmap
        headers       => ['User-Agent' => $agent],
        %args
    }, $class;
}

sub get {
    my ($self, $url) = @_;
    return $self->request(method => 'GET', url => $url);
}

sub request {
    my $self = shift;
    my %args = @_;

    my $timeout = $args{timeout};
    $timeout = $self->{timeout} if not defined $timeout;

    my ($scheme, $host, $port, $path_query) = do {
        if (defined(my $url = $args{url})) {
            if (ref $url) {
                ($url->scheme, $url->host, $url->port, $url->path_query);
            } else {
                $url =~ m{\A ([a-z]+) :// ([^/:]+) (?::(\d+))? (.*) }xms
                    or Carp::croak("malformed URL: $url");
                ($1, $2, $3 || 80, $4 || '/');
            }
        } else {
            ('http', $args{host}, $args{port} || 80, $args{path_query} || '/');
        }
    };

    if($scheme ne 'http') {
        Carp::croak("unsupported scheme: $scheme");
    }
    if(not defined $host) {
        Carp::croak("missing host name in arguments");
    }

    local $SIG{PIPE} = 'IGNORE';
    my $sock;
    if ($self->{sock_cache} && $self->{sock_cache}->{host} eq $host && $self->{sock_cache}->{port}  eq $port) {
        $sock = $self->{sock_cache}->{sock};
    } else {
        my ($iaddr, $sock_addr);
        if (my $proxy = $ENV{HTTP_PROXY}) {
            my $uri = URI->new($proxy);
            $iaddr = inet_aton($uri->host)
                or Carp::croak("cannot detect host name: $uri->host, $!");
            $sock_addr = pack_sockaddr_in($uri->port, $iaddr);
        } else {
            $iaddr = inet_aton($host)
                or Carp::croak("cannot detect host name: $host, $!");
            $sock_addr = pack_sockaddr_in($port, $iaddr);
        }
        socket($sock, PF_INET, SOCK_STREAM, 0)
            or Carp::croak("Cannot create socket: $!");
        connect($sock, $sock_addr)
            or Carp::croak("cannot connect to $host, $port: $!");
        setsockopt( $sock, IPPROTO_TCP, TCP_NODELAY, 1 )
          or Carp::croak("setsockopt(TCP_NODELAY) failed:$!");
        if ($^O eq 'MSWin32') {
            my $tmp = 1;
            ioctl( $sock, 0x8004667E, \$tmp )
              or Carp::croak("Can't set flags for the socket: $!");
        } else {
            my $flags = fcntl( $sock, F_GETFL, 0 )
              or Carp::croak("Can't get flags for the socket: $!");
            $flags = fcntl( $sock, F_SETFL, $flags | O_NONBLOCK )
              or Carp::croak("Can't set flags for the socket: $!");
        }

        {
            # no buffering
            my $orig = select();
            select($sock); $|=1;
            select($orig);
        }
    }

    # write request
    {
        my $method = $args{method} || 'GET';
        my $p = "$method $path_query HTTP/1.1\015\012Host: $host:$port\015\012";
        my @headers = @{$self->{headers}};
        if ($args{headers}) {
            push @headers, @{$args{headers}};
        }
        for (my $i = 0; $i < @headers; $i += 2) {
            $p .= $headers[$i] . ': ' . $headers[$i+1] . "\015\012";
        }
        $p .= "\015\012";
        $self->write_all($sock, $p, $timeout)
            or return $self->_r500("Failed to send HTTP request: $!");
        if (my $content = $args{content}) {
            $self->write_all($sock, $content, $timeout)
                or return $self->_r500("Failed to send content: $!");
        }
    }

    # read response
    my $buf = '';
    my $last_len = 0;
    my $res_status;
    my $res_msg;
    my $res_headers;
    my $res_content;
    my $res_connection;
    my $res_minor_version;
    my $res_content_length;
    my $res_transfer_encoding;
    my $res_location;
  LOOP: while (1) {
        my $read = $self->read_timeout($sock,
            \$buf, $self->{bufsize}, length($buf), $timeout );
        if (not defined $read) {
            return $self->_r500("error while reading from socket: $!");
        } elsif ( $read == 0 ) {    # eof
            return $self->_r500("Unexpected EOF");
        }
        else {
            ( $res_minor_version, $res_status, $res_msg, $res_content_length, $res_connection, $res_location, $res_transfer_encoding, $res_headers, my $ret ) =
              parse_http_response( $buf, $last_len );
            if ( $ret == -1 ) {
                return $self->_r500("Invalid HTTP response");
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

    # TODO: deflate support
    if ($res_transfer_encoding eq 'chunked') {
        $res_content = $self->_read_body_chunked($sock,
            $res_content, $timeout);
    } else {
        $res_content = $self->_read_body_normal($sock,
            $res_content, $res_content_length, $timeout);
    }

    my $max_redirects = $args{max_redirects} || $self->{max_redirects};
    if ($res_location && $max_redirects && $res_status =~ /^30[123]$/) {
        return $self->request(
            @_,
            url           => $res_location,
            max_redirects => $max_redirects - 1,
        );
    }

    # manage cache
    if ($res_content_length == -1
            || $res_minor_version == 0
            || lc($res_connection) eq 'close') {
        delete $self->{sock_cache};
        undef $sock;
    } else {
        $self->{sock_cache}->{sock} = $sock;
        $self->{sock_cache}->{host} = $host;
        $self->{sock_cache}->{port} = $port;
    }
    return ($res_status, $res_msg, $res_headers, $res_content);
}

sub _read_body_chunked {
    my ($self, $sock, $res_content, $timeout) = @_;

    my $buf = $res_content;
    my $ret;
  READ_LOOP: while (1) {
        if (
            my ( $header, $next_len ) = (
                $buf =~
                  /^
                    (
                        ([0-9a-fA-F]+)              # hex
                        (?:;$HTTP_TOKEN(?:=(?:$HTTP_TOKEN|$HTTP_QUOTED_STRING)))*  # chunk-extention
                        \015\012                    # crlf
                    )
                /x
            )
          )
        {
            if ($next_len eq '0') {
                $buf = substr($buf, length($header));
                last READ_LOOP;
            }
            $next_len = hex($next_len);

            $buf = substr($buf, length($header)); # remove header from buf.
            # +2 means trailing CRLF
          READ_CHUNK: while ( $next_len+2 > length($buf) ) {
                my $readed = $self->read_timeout( $sock,
                    \$buf, $self->{bufsize}, length($buf), $timeout );
                if ( not defined $readed ) {
                    if ( $? == EAGAIN ) {
                        next READ_CHUNK;
                    }
                    else {
                        Carp::croak("cannot read chunk: $!");
                    }
                }
            }
            $ret .= substr($buf, 0, $next_len);
            $buf = substr($buf, $next_len+2);
            if (length($buf) > 0) {
                next; # re-parse header
            }
        }

        my $readed = $self->read_timeout( $sock,
            \$buf, $self->{bufsize}, length($buf), $timeout );
        if ( not defined $readed ) {
            next READ_LOOP if $? == EAGAIN;
        } elsif ($readed == 0) {
            Carp::croak("unexpected eof while reading packets");
        }
    }
    $self->_read_body_normal($sock, $buf, 2, $timeout); # read last crlf
    return $ret;
}

sub _read_body_normal {
    my ($self, $sock, $res_content, $res_content_length, $timeout) = @_;

    my $sent_length = length($res_content);
    READ_LOOP: while ($res_content_length == -1 || $res_content_length != $sent_length) {
        my $bufsize = $self->{bufsize};
        if ($res_content_length != -1 && $res_content_length - $sent_length < $bufsize) {
            $bufsize = $res_content_length - $sent_length;
        }
        # TODO: save to fh
        my $readed = $self->read_timeout($sock, \my $buf, $bufsize, 0, $timeout);
        if (not defined $readed) {
            next READ_LOOP if $? == EAGAIN;
        }
        if ($readed == 0) {
            # eof
            last READ_LOOP;
        }
        $res_content .= $buf;
        $sent_length += $readed;
    }
    return $res_content;
}


# I/O with tmeout (stolen from Starlet/kazuho++)

sub do_select {
    my($self, $is_write, $sock, $timeout) = @_;
    # wait for data
    my($rfd, $wfd, $efd);
    while (1) {
        $efd = '';
        vec($efd, fileno($sock), 1) = 1;
        if ($is_write) {
            ($rfd, $wfd) = ('', $efd);
        } else {
            ($rfd, $wfd) = ($efd, '');
        }
        my $start_at = time;
        my $nfound   = select($rfd, $wfd, $efd, $timeout);
        $timeout    -= (time - $start_at);
        return 1 if $nfound;
        return 0 if $timeout <= 0;
    }
    die 'not reached';
}

# returns value returned by I/O syscalls, or undef on timeout or network error
#   sub do_io {
#       my ($self, $is_write, $sock, $buf, $len, $off, $timeout) = @_;
#       my $ret;
#       unless ($is_write) {
#           $self->do_select($is_write, $sock, $timeout) or return undef;
#       }
#       while(1) {
#           # try to do the IO
#           if ($is_write) {
#               $ret = syswrite $sock, $buf, $len, $off
#                   and return $ret;
#           } else {
#               $ret = sysread $sock, $$buf, $len, $off
#                   and return $ret;
#           }
#           unless (!defined($ret)
#                       && ($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK)) {
#               return undef;
#           }
#           $self->do_select($is_write, $sock, $timeout) or return undef;
#       }
#   }

# returns (positive) number of bytes read, or undef if the socket is to be closed
sub read_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    my $ret;
    $self->do_select(0, $sock, $timeout) or return undef;
    while(1) {
        # try to do the IO
        $ret = sysread $sock, $$buf, $len, $off
            and return $ret;
        unless (!defined($ret)
                     && ($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK)) {
            return undef;
        }
        $self->do_select(0, $sock, $timeout) or return undef;
    }
}

# returns (positive) number of bytes written, or undef if the socket is to be closed
sub write_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    my $ret;
    while(1) {
        # try to do the IO
        $ret = syswrite $sock, $buf, $len, $off
            and return $ret;
        unless (!defined($ret)
                     && ($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK)) {
            return undef;
        }
        $self->do_select(1, $sock, $timeout) or return undef;
    }
}

# writes all data in buf and returns number of bytes written or undef if failed
sub write_all {
    my ($self, $sock, $buf, $timeout) = @_;
    my $off = 0;
    while (my $len = length($buf) - $off) {
        my $ret = $self->write_timeout($sock, $buf, $len, $off, $timeout)
            or return undef;
        $off += $ret;
    }
    return $off;
}


sub _r500 {
    my($self, $message) = @_;
    delete $self->{sock_cache};
    $message ||= 'Internal Server Error';
    return(500, 'Internal Server Error',
        ['Content-Length' => length($message)], $message);
}

1;
__END__

=encoding utf8

=head1 NAME

Furl - Lightning-fast URL fetcher

=head1 SYNOPSIS

    use Furl;

    my $furl = Furl->new(agent => ...);
    my ($code, $msg, $headers, $body) = $furl->request(
        method => 'GET',
        host   => 'example.com',
        port   => 80,
        path   => '/'
    );
    # or
    my ($code, $msg, $headers, $body) = $furl->request(
        method => 'GET',
        host   => 'example.com',
        port   => 80,
        path   => '/'
        save_to_tmpfile => 1,
    );

=head1 DESCRIPTION

Furl is yet another http client library.

=head1 INTEGRATE WITH HTTP::Response

Some useful libraries require the instance of HTTP::Response for argument.
You can easy to create the instance of it.

    my $res = HTTP::Response->new($furl->get($url));

=head1 TODO

    - form serializer
        seraizlie_x_www_url_encoded(foo => bar, baz => 1);
    - idn support(with Net-IDN-Encode?)
    - proxy support
    - env_proxy support
    - cookie_jar support
    - ssl support

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
