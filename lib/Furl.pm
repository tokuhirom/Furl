package Furl;
use strict;
use warnings;
use 5.008;
our $VERSION = '0.01';

#use Smart::Comments;
use Carp ();
use XSLoader;

use Scalar::Util ();
use Errno qw(EAGAIN EINTR EWOULDBLOCK);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK SEEK_SET SEEK_END);
use Socket qw(
    PF_INET SOCK_STREAM
    IPPROTO_TCP
    TCP_NODELAY
    inet_aton
    pack_sockaddr_in
);

XSLoader::load __PACKAGE__, $VERSION;

# ref. RFC 2616, 3.5 Content Codings:
#     For compatibility with previous implementations of HTTP,
#     applications SHOULD consider "x-gzip" and "x-compress" to be
#     equivalent to "gzip" and "compress" respectively.
# ("compress" is not supported, though)
my %COMPRESSED = map { $_ => undef } qw(gzip x-gzip deflate);

my $HTTP_TOKEN         = '[^\x00-\x31\x7F]+';
my $HTTP_QUOTED_STRING = q{"([^"]+|\\.)*"};

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;

    my @headers = (
        'User-Agent' => (delete($args{agent}) || __PACKAGE__ . '/' . $VERSION),
    );
    if(defined $args{headers}) {
        push @headers, @{delete $args{headers}};
    }
    bless {
        timeout       => 10,
        max_redirects => 7,
        bufsize       => 10*1024, # no mmap
        headers       => \@headers,
        proxy         => '',
        %args
    }, $class;
}


sub Furl::Util::header_get {
    my ($headers, $key) = (shift, lc shift);
    for (my $i=0; $i<@$headers; $i+=2) {
        return $headers->[$i+1] if lc($headers->[$i]) eq $key;
    }
    return undef;
}

sub Furl::Util::uri_escape {
    my($s) = @_;
    utf8::encode($s);
    # escape unsafe chars (defined by RFC 3986)
    $s =~ s/ ([^A-Za-z0-9\-\._~]) / sprintf '%%%02X', ord $1 /xmsge;
    return $s;
}

sub Furl::Util::make_x_www_form_urlencoded {
    my($content) = @_;
    my @params;
    my @p = ref($content) eq 'HASH'  ? %{$content}
          : ref($content) eq 'ARRAY' ? @{$content}
          : Carp::croak("Cannot coerce $content to x-www-form-urlencoded");
    while ( my ( $k, $v ) = splice @p, 0, 2 ) {
        push @params,
            Furl::Util::uri_escape($k) . '=' . Furl::Util::uri_escape($v);
    }
    return join( "&", @params );
}

sub Furl::Util::requires {
    my($file, $feature) = @_;
    return if exists $INC{$file};
    unless(eval { require $file }) {
        $file =~ s/ \.pm \z//xms;
        $file =~ s{/}{::}g;
        Carp::croak(
            "$feature requires $file, but it is not available."
            . " Please install $file using your prefer CPAN client"
            . " (App::cpanminus is recommended)"
        );
    }
}

sub get {
    my ($self, $url, $headers) = @_;
    $self->request( method => 'GET',
        url => $url, headers => $headers );
}

sub head {
    my ($self, $url, $headers) = @_;
    $self->request( method => 'HEAD',
        url => $url, headers => $headers );
}

sub post {
    my ( $self, $url, $headers, $content ) = @_;
    $self->request( method => 'POST',
        url => $url, headers => $headers, content => $content );
}

sub put {
    my ( $self, $url, $headers, $content ) = @_;
    $self->request( method => 'PUT',
        url => $url, headers => $headers, content => $content );
}

sub delete {
    my ($self, $url, $headers) = @_;
    $self->request( method => 'DELETE',
        url => $url, headers => $headers );
}

# returns $scheme, $host, $port, $path_query
sub _parse_url {
    my($self, $url) = @_;
    $url =~ m{\A
        ([a-z]+)       # scheme
        ://
        ([^/:]+)       # host
        (?: : (\d+) )? # port
        (?: (/ .*)  )? # path_query
    \z}xms or Carp::croak("Passed malformed URL: $url");
    return( $1, $2, $3, $4 );
}

sub env_proxy {
    my $self = shift;
    $self->{proxy} = $ENV{HTTP_PROXY} || '';
    $self;
}

# XXX more better naming?
sub request_with_http_request {
    my ($self, $req, %args) = @_;
    my $headers = +[
        map {
            my $k = $_;
            map { ( $k => $_ ) } $req->headers->header($_);
          } $req->headers->header_field_names
    ];
    $self->request(
        url     => $req->uri,
        method  => $req->method,
        content => $req->content,
        headers => $headers,
        %args
    );
}

sub request {
    my $self = shift;
    my %args = @_;

    my $timeout = $args{timeout};
    $timeout = $self->{timeout} if not defined $timeout;

    my ($scheme, $host, $port, $path_query) = do {
        if (defined(my $url = $args{url})) {
            $self->_parse_url($url);
        }
        else {
            ($args{scheme}, $args{host}, $args{port}, $args{path_query});
        }
    };

    if (not defined $scheme) {
        $scheme = 'http';
    } elsif($scheme ne 'http' && $scheme ne 'https') {
        Carp::croak("Unsupported scheme: $scheme");
    }
    if(not defined $host) {
        Carp::croak("Missing host name in arguments");
    }
    if(not defined $port) {
        if ($scheme eq 'http') {
            $port = 80;
        } else {
            $port = 443;
        }
    }
    if(not defined $path_query) {
        $path_query = '/';
    }

    if ($host =~ /[^A-Za-z0-9.-]/) {
        Furl::Util::requires('Net/IDN/Encode.pm',
            'Internationalized Domain Name (IDN)');
        $host = Net::IDN::Encode::domain_to_ascii($host);
    }


    local $SIG{PIPE} = 'IGNORE';
    my $sock = $self->get_conn_cache($host, $port);
    if(not defined $sock) {
        my ($_host, $_port);
        if ($self->{proxy}) {
            (undef, $_host, $_port, undef)
                = $self->_parse_url($self->{proxy});
        }
        else {
            $_host = $host;
            $_port = $port;
        }

        if ($scheme eq 'http') {
            $sock = $self->connect($_host, $_port);
        } else {
            $sock = $self->{proxy}
                ? $self->connect_ssl_over_proxy(
                    $_host, $_port, $host, $port, $timeout)
                : $self->connect_ssl($_host, $_port);
        }
        setsockopt( $sock, IPPROTO_TCP, TCP_NODELAY, 1 )
          or Carp::croak("Failed to setsockopt(TCP_NODELAY): $!");
        if ($^O eq 'MSWin32') {
            my $tmp = 1;
            ioctl( $sock, 0x8004667E, \$tmp )
              or Carp::croak("Cannot set flags for the socket: $!");
        } else {
            my $flags = fcntl( $sock, F_GETFL, 0 )
              or Carp::croak("Cannot get flags for the socket: $!");
            $flags = fcntl( $sock, F_SETFL, $flags | O_NONBLOCK )
              or Carp::croak("Cannot set flags for the socket: $!");
        }

        {
            # no buffering
            my $orig = select();
            select($sock); $|=1;
            select($orig);
        }
    }

    # write request
    my $method = $args{method} || 'GET';
    {
        if($self->{proxy}) {
            $path_query = "$scheme://$host:$port$path_query";
        }
        my $p = "$method $path_query HTTP/1.1\015\012"
              . "Host: $host:$port\015\012";

        my @headers = @{$self->{headers}};
        if ($args{headers}) {
            push @headers, @{$args{headers}};
        }

        my $content       = $args{content};
        my $content_is_fh = 0;
        if(defined $content) {
            $content_is_fh = Scalar::Util::openhandle($content);
            if(!$content_is_fh && ref $content) {
                $content = Furl::Util::make_x_www_form_urlencoded($content);
                if(!defined Furl::Util::header_get(\@headers, 'Content-Type')) {
                    push @headers, 'Content-Type'
                        => 'application/x-www-form-urlencoded';
                }
            }
            if(!defined Furl::Util::header_get(\@headers, 'Content-Length')) {
                my $content_length;
                if($content_is_fh) {
                    my $assert = sub {
                        $_[0] or Carp::croak(
                            "Failed to $_[1] for Content-Length: $!",
                        );
                    };
                    $assert->(defined(my $cur_pos = tell($content)), 'tell');
                    $assert->(seek($content, 0, SEEK_END),           'seek');
                    $assert->(defined(my $end_pos = tell($content)), 'tell');
                    $assert->(seek($content, $cur_pos, SEEK_SET),    'seek');

                    $content_length = $end_pos - $cur_pos;
                }
                else {
                    $content_length = length($content);
                }
                push @headers, 'Content-Length' => $content_length;
            }
        }

        for (my $i = 0; $i < @headers; $i += 2) {
            my $val = $headers[ $i + 1 ];
            # the de facto standard way to handle [\015\012](by kazuho-san)
            $val =~ s/[\015\012]/ /g;
            $p .= $headers[$i] . ": $val\015\012";
        }
        $p .= "\015\012";
        ### $p
        $self->write_all($sock, $p, $timeout)
            or return $self->_r500("Failed to send HTTP request: $!");
        if (defined $content) {
            if ($content_is_fh) {
                my $ret;
                SENDFILE: while (1) {
                    $ret = read($content, my $buf, $self->{bufsize});
                    if (not defined $ret) {
                        Carp::croak("Failed to read request content: $!");
                    } elsif ($ret == 0) {
                        last SENDFILE;
                    }
                    $self->write_all($sock, $buf, $timeout)
                        or return $self->_r500("Failed to send content: $!");
                }
            } else { # simple string
                $self->write_all($sock, $content, $timeout)
                    or return $self->_r500("Failed to send content: $!");
            }
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
    my $res_content_encoding;
    my $res_location;
    my $rest_header;
  LOOP: while (1) {
        my $n = $self->read_timeout($sock,
            \$buf, $self->{bufsize}, length($buf), $timeout );
        if(!$n) { # error or eof
            return $self->_r500(
                !defined($n)
                    ? "Cannot read response header: $!"
                    : "Unexpected EOF while reading response header"
            );
        }
        else {
            ( $res_minor_version, $res_status, $res_msg, $res_content_length, $res_connection, $res_location, $res_transfer_encoding, $res_content_encoding, $res_headers, my $ret ) =
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
                $rest_header = substr( $buf, $ret );
                last LOOP;
            }
        }
    }

    if (my $fh = $args{write_file}) {
        $res_content = Furl::PartialWriter->new(
            append => sub { print $fh @_ },
        );
    } elsif (my $coderef = $args{write_code}) {
        $res_content = Furl::PartialWriter->new(
            append => sub {
                $coderef->($res_status, $res_msg, $res_headers, @_);
            },
        );
    }
    else {
        $res_content = '';
    }

    if (exists $COMPRESSED{ $res_content_encoding }) {
        Furl::Util::requires('Compress/Raw/Zlib.pm', 'Content-Encoding');

        my $inflated        = '';
        my $old_res_content = $res_content;
        my $assert_z_ok     = sub {
            $_[0] == Compress::Raw::Zlib::Z_OK()
                or Carp::croak("Uncompressing error: $_[0]");
        };
        my($z, $status) = Compress::Raw::Zlib::Inflate->new(
            -WindowBits => Compress::Raw::Zlib::WANT_GZIP_OR_ZLIB(),
        );
        $assert_z_ok->($status);
        $res_content = Furl::PartialWriter->new(
            append => sub {
                $assert_z_ok->( $z->inflate($_[0], \my $deflated) );
                $old_res_content .= $deflated;
            },
            finalize => sub {
                return ref($old_res_content)
                    ? $old_res_content->finalize
                    : $old_res_content;
            },
        );
    }

    my @err;
    if ($res_transfer_encoding eq 'chunked') {
        @err = $self->_read_body_chunked($sock,
            $rest_header, $timeout, \$res_content);
    } else {
        $res_content .= $rest_header;
        @err = $self->_read_body_normal($sock,
            \$res_content, length($rest_header), $res_content_length, $timeout);
    }
    if(@err) {
        return @err;
    }

    my $max_redirects = $args{max_redirects} || $self->{max_redirects};
    if ($res_location && $max_redirects && $res_status =~ /^30[123]$/) {
        # Note: RFC 1945 and RFC 2068 specify that the client is not allowed
        # to change the method on the redirected request.  However, most
        # existing user agent implementations treat 302 as if it were a 303
        # response, performing a GET on the Location field-value regardless
        # of the original request method. The status codes 303 and 307 have
        # been added for servers that wish to make unambiguously clear which
        # kind of reaction is expected of the client.
        return $self->request(
            @_,
            method        => $res_status eq '301' ? $method : 'GET',
            url           => $res_location,
            max_redirects => $max_redirects - 1,
        );
    }

    # manage cache
    if ($res_content_length == -1
            || $res_minor_version == 0
            || lc($res_connection) eq 'close') {
        $self->remove_conn_cache($host, $port);
    } else {
        $self->add_conn_cache($host, $port, $sock);
    }
    return ($res_status, $res_msg, $res_headers,
            ref($res_content) ? $res_content->finalize() : $res_content);
}

# connects to $host:$port and returns $socket
# You can override this methond in your child class.
sub connect :method {
    my($self, $host, $port) = @_;
    my $sock;
    my $iaddr = inet_aton($host)
        or Carp::croak("Cannot resolve host name: $host, $!");
    my $sock_addr = pack_sockaddr_in($port, $iaddr);

    socket($sock, PF_INET, SOCK_STREAM, 0)
        or Carp::croak("Cannot create socket: $!");
    connect($sock, $sock_addr)
        or Carp::croak("Cannot connect to ${host}:${port}: $!");
    return $sock;
}

# connect SSL socket.
# You can override this methond in your child class, if you want to use Crypt::SSLeay or some other library.
# @return file handle like object
sub connect_ssl {
    my ($self, $host, $port) = @_;
    Furl::Util::requires('IO/Socket/SSL.pm', 'SSL');

    return IO::Socket::SSL->new( PeerHost => $host, PeerPort => $port )
      or Carp::croak("Cannot create SSL connection: $!");
}

sub connect_ssl_over_proxy {
    my ($self, $proxy_host, $proxy_port, $host, $port, $timeout) = @_;
    Furl::Util::requires('IO/Socket/SSL.pm', 'SSL');

    my $sock = $self->connect($proxy_host, $proxy_port);

    my $p = "CONNECT $host:$port HTTP/1.0\015\012Server: $host\015\012\015\012";
    $self->write_all($sock, $p, $timeout)
        or return $self->_r500("Failed to send HTTP request to proxy: $!");
    my $buf = '';
    my $read = $self->read_timeout($sock,
        \$buf, $self->{bufsize}, length($buf), $timeout);
    if (not defined $read) {
        Carp::croak("Cannot read proxy response: $!");
    } elsif ( $read == 0 ) {    # eof
        Carp::croak("Unexpected EOF while reading proxy response");
    } elsif ( $buf !~ /^HTTP\/1.[01] 200 Connection established\015\012/ ) {
        Carp::croak("Invalid HTTP Response via proxy");
    }

    IO::Socket::SSL->start_SSL( $sock, Timeout => $timeout )
      or Carp::croak("Cannot start SSL connection: $!");
}

# following three connections are related to connection cache for keep-alive.
# If you want to change the cache strategy, you can override in child classs.
sub get_conn_cache {
    my ( $self, $host, $port ) = @_;

    my $cache = $self->{sock_cache};
    if ($cache && $cache->[0] eq "$host:$port") {
        return $cache->[1];
    } else {
        return undef;
    }
}

sub remove_conn_cache {
    my ($self, $host, $port) = @_;

    delete $self->{sock_cache};
}

sub add_conn_cache {
    my ($self, $host, $port, $sock) = @_;

    $self->{sock_cache} = ["$host:$port" => $sock];
}

sub _read_body_chunked {
    my ($self, $sock, $rest_header, $timeout, $res_content) = @_;

    my $buf = $rest_header;
  READ_LOOP: while (1) {
        if (
            my ( $header, $next_len ) = (
                $buf =~
                  m{\A (                 # header
                        ( [0-9a-fA-F]+ ) # next_len (hex number)
                        (?:;
                            $HTTP_TOKEN
                            =
                            (?: $HTTP_TOKEN | $HTTP_QUOTED_STRING )
                        )*               # optional chunk-extentions
                        [ ]*             # www.yahoo.com adds spaces here.
                                         # Is this valid?
                        \015\012         # CR+LF
                  ) }xmso
            )
          )
        {
            $buf = substr($buf, length($header)); # remove header from buf
            if ($next_len eq '0') {
                last READ_LOOP;
            }
            $next_len = hex($next_len);

            # +2 means trailing CRLF
          READ_CHUNK: while ( $next_len+2 > length($buf) ) {
                my $n = $self->read_timeout( $sock,
                    \$buf, $self->{bufsize}, length($buf), $timeout );
                if ( not defined $n ) {
                    return $self->_r500("Cannot read chunk: $!");
                }
            }
            $$res_content .= substr($buf, 0, $next_len);
            $buf = substr($buf, $next_len+2);
            if (length($buf) > 0) {
                next; # re-parse header
            }
        }

        my $n = $self->read_timeout( $sock,
            \$buf, $self->{bufsize}, length($buf), $timeout );
        if (!$n) {
            return $self->_r500(
                !defined($n)
                    ? "Cannot read chunk: $!"
                    : "Unexpected EOF while reading packets"
            );
        }
    }
    # read last CRLF
    return $self->_read_body_normal(
        $sock, \$buf, length($buf), 2, $timeout);
}

sub _read_body_normal {
    my ($self, $sock, $res_content, $nread, $res_content_length, $timeout) = @_;
  READ_LOOP: while ($res_content_length == -1 || $res_content_length != $nread) {
        my $bufsize = $self->{bufsize};
        my $n = $self->read_timeout($sock, \my $buf, $bufsize, 0, $timeout);
        if (!$n) {
            return $self->_r500(
                !defined($n)
                    ? "Cannot read content body: $!"
                    : "Unexpected EOF while reading content body"
            );
        }
        $$res_content .= $buf;
        $nread        += $n;
    }
    return;
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

# returns (positive) number of bytes read, or undef if the socket is to be closed
sub read_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    my $ret;
    $self->do_select(0, $sock, $timeout) or return undef;
    while(1) {
        # try to do the IO
        defined($ret = sysread($sock, $$buf, $len, $off))
            and return $ret;

        unless ($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK) {
            return undef;
        }
        # on EINTER/EAGAIN/EWOULDBLOCK
        $self->do_select(0, $sock, $timeout) or return undef;
    }
}

# returns (positive) number of bytes written, or undef if the socket is to be closed
sub write_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    my $ret;
    while(1) {
        # try to do the IO
        defined($ret = syswrite($sock, $buf, $len, $off))
            and return $ret;

        unless ($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK) {
            return undef;
        }
        # on EINTER/EAGAIN/EWOULDBLOCK
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
    $self->remove_conn_cache();
    $message = Carp::shortmess($message); # add lineno and filename
    return(500, 'Internal Server Error',
        ['Content-Length' => length($message)], $message);
}

# utility class
{
    package Furl::PartialWriter;
    use overload '.=' => 'append', fallback => 1;
    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }
    sub append {
        my($self, $partial) = @_;
        $self->{append}->($partial);
        return $self;
    }
    sub finalize {
        my($self) = @_;
        if($self->{finalize}) {
            return $self->{finalize}->();
        }
        return undef;
    }
}

1;
__END__

=encoding utf8

=head1 NAME

Furl - Lightning-fast URL fetcher

=head1 SYNOPSIS

    use Furl;

    my $furl = Furl->new(
        agent   => 'MyGreatUA/2.0',
        timeout => 10,
    );

    my ($code, $msg, $headers, $body) = $furl->request(
        method => 'GET',
        host   => 'example.com',
        port   => 80,
        path   => '/'
    );
    # or
    my ($code, $msg, $headers, $body) = $furl->get('http://example.com/');
    my ($code, $msg, $headers, $body) = $furl->post(
        'http://example.com/', # URL
        [...],                 # headers
        [ foo => 'bar' ],      # form data (HashRef/FileHandle are also okay)
    );

    # Accept-Encoding is supported but optional
    $furl = Furl->new(
        headers => [ 'Accept-Encoding' => 'gzip' ],
    );
    my $body = $furl->get('http://example.com/some/compressed');

=head1 DESCRIPTION

Furl is yet another HTTP client library. LWP is the de facto standard HTTP
client for Perl5, but it is too slow for some critical jobs, and too complex
for weekend hacking. Furl will resolves these issues. Enjoy it!

This library is an B<alpha> software. Any APIs will change without notice.

=head1 INTERFACE

=head2 Class Methods

=head3 C<< Furl->new(%args | \%args) :Furl >>

Creates and returns a new Furl client with I<%args>. Dies on errors.

I<%args> might be:

=over

=item agent :Str = "Furl/$VERSION"

=item timeout :Int = 10

=item max_redirects :Int = 7

=item proxy :Str

=item headers :ArrayRef

=back

=head2 Instance Methods

=head3 C<< $furl->request(%args) :($code, $msg, \@headers, $body) >>

Sends an HTTP request to a specified URL and returns a status code,
status message, response headers, response body respectively.

I<%args> might be:

=over

=item scheme :Str = "http"

=item host :Str

=item port :Int = 80

=item path_query :Str = "/"

=item url :Str

You can use C<url> instead of C<scheme>, C<host>, C<port> and C<path_query>.

=item headers :ArrayRef

=item content : Str | ArrayRef[Str] | HashRef[Str] | FileHandle

=back

=head3 C<< $furl->get($url :Str, $headers :ArrayRef[Str] ) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->head($url :Str, $headers :ArrayRef[Str] ) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->post($url :Str, $headers :ArrayRef[Str], $content :Any) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->put($url :Str, $headers :ArrayRef[Str], $content :Any) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->delete($url :Str, $headers :ArrayRef[Str] ) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->request_with_http_request($req :HTTP::Request) :List >>

This is an easy-to-use alias to C<request()>.

=head3 C<< $furl->env_proxy() >>

Loads proxy settings from C<< $ENV{HTTP_PROXY} >>.

=head1 INTEGRATE WITH HTTP::Response

Some useful libraries require HTTP::Response instances for their arguments.
You can easily create its instance from the result of C<request()> and other HTTP request methods.

    my $res = HTTP::Response->new($furl->get($url));

=head1 PROJECT POLICY

=over 4

=item Why IO::Socket::SSL?

Net::SSL is not well documented.

=item Why env_proxy is optional?

Environment variables are highly dependent on users' environments.
It makes confusing users.

=item Supported Operating Systems.

Linux 2.6 or higher, OSX Tiger or higher, Windows XP or higher.

And we can support other operating systems if you send a patch.

=item Why Furl does not support chunked upload?

There are reasons why chunked POST/PUTs should not be generally used.  You cannot send chunked requests unless the peer server at the other end of the established TCP connection is known to be a HTTP/1.1 server.  However HTTP/1.1 servers disconnect their persistent connection quite quickly (when comparing to the time they wait for the first request), so it is not a good idea to post non-idempotent requests (e.g. POST, PUT, etc.) as a succeeding request over persistent connections.  The two facts together makes using chunked requests virtually impossible (unless you _know_ that the server supports HTTP/1.1), and this is why we decided that supporting the feature is of high priority.

=back

=head1 FAQ

=over 4

=item How to make content body by CodeRef?

use L<Tie::Handle>. If you have any reason to support this, please send a github ticket.

=item How to use cookie_jar?

Furl does not support cookie_jar. You can use L<HTTP::Cookies>, L<HTTP::Request>, L<HTTP::Response> like following.

    my $f = Furl->new();
    my $cookies = HTTP::Cookies->new();
    my $req = HTTP::Request->new(...);
    $cookies->add_cookie_header($req);
    my $res = HTTP::Response->new($f->request_with_http_request($req));
    $cookies->extract_cookies($res);
    # and use $res.

=item How to use gzip/deflate compressed communication?

Add an B<Accept-Encoding> header to your request. Furl inflates response bodies transparently according to the B<Content-Encoding> response header.

=back

=head1 TODO

Before First Release

    - Docs, docs, docs!

After First Release

    - AnyEvent::Furl?
    - change the parser_http_response args. and backport to HTTP::Response::Parser.
        my($headers, $retcode, ...) = parse_http_response($buf, $last_len, @specific_headers)
    - use HTTP::Response::Parser
    - PP version(by HTTP::Respones::Parser)
    - multipart/form-data support

=head1 OPTIONAL FEATURES

=head2 Internationalized Domain Name (IDN)

This feature requires Net::IDN::Encode.

=head2 SSL

This feature requires IO::Socket::SSL.

=head2 Content-Encoding (deflate, gzip)

This feature requires Compress::Raw::Zlib.

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

gfx

=head1 THANKS TO

Kazuho Oku

mala

mattn

=head1 SEE ALSO

L<LWP>

HTTP specs:
L<http://www.w3.org/Protocols/HTTP/1.0/spec.html>
L<http://www.w3.org/Protocols/HTTP/1.1/spec.html>

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
