package Furl;
use strict;
use warnings;
use 5.00800;
our $VERSION = '0.01';

use Carp ();
use Errno qw(EAGAIN);
use XSLoader;
use Socket qw/inet_aton PF_INET SOCK_STREAM pack_sockaddr_in/;

XSLoader::load __PACKAGE__, $VERSION;

my $HTTP_TOKEN = '[^\x00-\x31\x7F]+';
my $HTTP_QUOTED_STRING = q{"([^"]+|\\.)*"};

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    my $agent = __PACKAGE__ . '/' . $VERSION;
    my $timeout = $args{timeout} || 10;
    bless {
        parse_header => 1,
        timeout => $timeout,
        max_redirects => 7,
        bufsize => 10*1024, # no mmap
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

    my ($host, $port, $path_query) = do {
        if ($args{url}) {
            my $url = $args{url};
            if (ref $url) {
                ($url->host, $url->port, $url->path_query);
            } else {
                $url =~ m{^http://([^/:]+)(?::(\d+))?(.*)$};
                ($1, $2 || 80, $3 || '/');
            }
        } else {
            ($args{host}, $args{port} || 80, $args{path_query} || '/');
        }
    };
    die "missing host name in arguments" unless defined $host;

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
        my $method = $args{method} || 'GET';
        my $p = "$method $path_query HTTP/1.1\015\012Host: $host:$port\015\012";
        if ($args{headers}) {
            for (my $i=0; $i<@{$args{headers}}; $i+=2) {
                $p .= $args{headers}->[$i] . ': ' . $args{headers}->[$i+1] . "\015\012";
            }
        }
        $p .= "\015\012";
        defined(syswrite($sock, $p, length($p))) or return $err->(500, [], ['Broken Pipe']);
        if (my $content = $args{content}) {
            defined(syswrite($sock, $content, length($content))) or die $!;
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
        my $read = sysread($sock, $buf, $self->{bufsize}, length($buf) );
        if (not defined $read || $read < 0) {
            die "error while reading from socket: $!";
        } elsif ( $read == 0 ) {    # eof
            return $err->(500, [], "Unexpected EOF: $!");
        }
        else {
            ( $res_minor_version, $res_status, $res_msg, $res_content_length, $res_connection, $res_location, $res_transfer_encoding, $res_headers, my $ret ) =
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
    # TODO: deflate support
    if ($res_transfer_encoding && $res_transfer_encoding eq 'chunked') {
        $res_content = $self->_read_body_chunked($sock, $res_content);
    } else {
        $res_content = $self->_read_body_normal($sock, $res_content, $res_content_length);
    }

    my $max_redirects = $args{max_redirects} || $self->{max_redirects};
    if ($res_status =~ /^30[123]$/ && $res_location && $max_redirects) {
        return $self->request(
            @_,
            url           => $res_location,
            max_redirects => $max_redirects - 1,
        );
    }

    # manage cache
    if ($res_content_length == -1 || $res_minor_version == 0 || ($res_connection && lc($res_connection) eq 'close')) {
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
    my ($self, $sock, $res_content) = @_;

    my $buf = $res_content;
    my $ret;
    my $need_read;
  READ_LOOP: while (1) {
        if ($need_read) {
            my $readed = sysread( $sock, $buf, $self->{bufsize}, length($buf) );
            if ( !defined $readed ) {
                next READ_LOOP if $? == EAGAIN;
            } elsif ($readed == 0) {
                die "unexpected eof while reading packets";
            }
        }

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
                my $readed =
                  sysread( $sock, $buf, $self->{bufsize}, length($buf) );
                if ( not defined $readed ) {
                    if ( $? == EAGAIN ) {
                        next READ_CHUNK;
                    }
                    else {
                        die "cannot read chunk: $!";
                    }
                }
            }
            $ret .= substr($buf, 0, $next_len);
            $buf = substr($buf, $next_len+2);
            if (length($buf) > 0) {
                $need_read = 0;
            }
        } else {
            $need_read++;
        }
    }
    $self->_read_body_normal($sock, $buf, 2); # read last crlf
    return $ret;
}

sub _read_body_normal {
    my ($self, $sock, $res_content, $res_content_length) = @_;

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
    return $res_content;
}

1;
__END__

=encoding utf8

=head1 NAME

Furl -

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
    - timeout
    - idn support(with Net-IDN-Encode?)
    - proxy support
    - env_proxy support
    - cookie_jar support
    - timeout support
    - ssl support

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
