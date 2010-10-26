package Furl;
use strict;
use warnings;
use 5.008;
our $VERSION = '0.04';

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

use constant WIN32 => $^O eq 'MSWin32';

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
        no_proxy      => '',
        sock_cache    => $class->new_conn_cache(),
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


sub Furl::Util::requires {
    my($file, $feature, $library) = @_;
    return if exists $INC{$file};
    unless(eval { require $file }) {
        if ($@ =~ /^Can't locate/) {
            $library ||= do {
                local $_ = $file;
                s/ \.pm \z//xms;
                s{/}{::}g;
                $_;
            };
            Carp::croak(
                "$feature requires $library, but it is not available."
                . " Please install $library using your prefer CPAN client"
            );
        } else {
            die $@;
        }
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

sub make_x_www_form_urlencoded {
    my($self, $content) = @_;
    my @params;
    my @p = ref($content) eq 'HASH'  ? %{$content}
          : ref($content) eq 'ARRAY' ? @{$content}
          : Carp::croak("Cannot coerce $content to x-www-form-urlencoded");
    while ( my ( $k, $v ) = splice @p, 0, 2 ) {
        foreach my $s($k, $v) {
            utf8::downgrade($s); # will die in wide characters
            # escape unsafe chars (defined by RFC 3986)
            $s =~ s/ ([^A-Za-z0-9\-\._~]) / sprintf '%%%02X', ord $1 /xmsge;
        }
        push @params, "$k=$v";
    }
    return join( "&", @params );
}

sub env_proxy {
    my $self = shift;
    $self->{proxy} = $ENV{HTTP_PROXY} || '';
    $self->{no_proxy} = $ENV{NO_PROXY} || '';
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

    my ($scheme, $host, $port, $path_query);
    if (defined(my $url = $args{url})) {
        ($scheme, $host, $port, $path_query) = $self->_parse_url($url);
    }
    else {
        ($scheme, $host, $port, $path_query) = @args{qw/scheme host port path_query/};
        if (not defined $host) {
            Carp::croak("Missing host name in arguments");
        }
    }

    if (not defined $scheme) {
        $scheme = 'http';
    } elsif($scheme ne 'http' && $scheme ne 'https') {
        Carp::croak("Unsupported scheme: $scheme");
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

    my $proxy = $self->{proxy};
    my $no_proxy = $self->{no_proxy};
    if ($proxy && $no_proxy) {
        if ($self->match_no_proxy($no_proxy, $host)) {
            undef $proxy;
        }
    }

    local $SIG{PIPE} = 'IGNORE';
    my $sock = $self->get_conn_cache($host, $port);
    if(not defined $sock) {
        my ($_host, $_port);
        if ($proxy) {
            (undef, $_host, $_port, undef)
                = $self->_parse_url($proxy);
        }
        else {
            $_host = $host;
            $_port = $port;
        }

        if ($scheme eq 'http') {
            $sock = $self->connect($_host, $_port);
        } else {
            $sock = $proxy
                ? $self->connect_ssl_over_proxy(
                    $_host, $_port, $host, $port, $timeout)
                : $self->connect_ssl($_host, $_port);
        }
        setsockopt( $sock, IPPROTO_TCP, TCP_NODELAY, 1 )
          or Carp::croak("Failed to setsockopt(TCP_NODELAY): $!");
        if (WIN32) {
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

        binmode $sock;
    }

    # write request
    my $method = $args{method} || 'GET';
    {
        if($proxy) {
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
                $content = $self->make_x_www_form_urlencoded($content);
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
            $val =~ tr/\015\012/ /;
            $p .= "$headers[$i]: $val\015\012";
        }
        $p .= "\015\012";
        $self->write_all($sock, $p, $timeout)
            or return $self->_r500("Failed to send HTTP request: $!");
        if (defined $content) {
            if ($content_is_fh) {
                my $ret;
                my $buf;
                SENDFILE: while (1) {
                    $ret = read($content, $buf, $self->{bufsize});
                    if (not defined $ret) {
                        Carp::croak("Failed to read request content: $!");
                    } elsif ($ret == 0) { # EOF
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
    my $rest_header;
    my $res_minor_version;
    my $res_status;
    my $res_msg;
    my @res_headers;
    my %res = (
        'connection'        => '',
        'transfer-encoding' => '',
        'content-encoding'  => '',
        'location'          => '',
        'content-length'    => undef,
    );
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
            my $ret;
            ( $res_minor_version, $res_status, $res_msg, $ret )
                =  parse_http_response( $buf, $last_len, \@res_headers, \%res );
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

    my $res_content;
    if (my $fh = $args{write_file}) {
        $res_content = Furl::FileStream->new( $fh );
    } elsif (my $coderef = $args{write_code}) {
        $res_content = Furl::CallbackStream->new(
            sub { $coderef->($res_status, $res_msg, \@res_headers, @_) }
        );
    }
    else {
        $res_content = '';
    }

    if (exists $COMPRESSED{ $res{'content-encoding'} }) {
        Furl::Util::requires('Furl/ZlibStream.pm', 'Content-Encoding', 'Compress::Raw::Zlib');

        $res_content = Furl::ZlibStream->new($res_content);
    }

    if($method ne 'HEAD') {
        my @err;
        if ( $res{'transfer-encoding'} eq 'chunked' ) {
            @err = $self->_read_body_chunked($sock,
                \$res_content, $rest_header, $timeout);
        } else {
            $res_content .= $rest_header;
            @err = $self->_read_body_normal($sock,
                \$res_content, length($rest_header),
                $res{'content-length'}, $timeout);
        }
        if(@err) {
            return @err;
        }
    }

    if ($res{location}) {
        my $max_redirects = $args{max_redirects} || $self->{max_redirects};
        if ($max_redirects && $res_status =~ /^30[123]$/) {
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
                url           => $res{location},
                max_redirects => $max_redirects - 1,
            );
        }
    }

    # manage cache
    if (   $res_minor_version == 0
        || lc($res{'connection'}) eq 'close'
        || !(    defined($res{'content-length'})
              || $res{'transfer-encoding'} eq 'chunked' )
        || $method eq 'HEAD') {
        $self->remove_conn_cache($host, $port);
    } else {
        $self->add_conn_cache($host, $port, $sock);
    }

    # return response.
    if (ref $res_content) {
        return ($res_status, $res_msg, \@res_headers, $res_content->get_response_string);
    } else {
        return ($res_status, $res_msg, \@res_headers, $res_content);
    }
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
sub new_conn_cache {
    return [''];
}

sub get_conn_cache {
    my ( $self, $host, $port ) = @_;

    my $cache = $self->{sock_cache};
    if ($cache->[0] eq "$host:$port") {
        return $cache->[1];
    } else {
        return undef;
    }
}

sub remove_conn_cache {
    my ($self, $host, $port) = @_;

    @{ $self->{sock_cache} } = ('');
    return;
}

sub add_conn_cache {
    my ($self, $host, $port, $sock) = @_;

    @{ $self->{sock_cache} } = ("$host:$port" => $sock);
    return;
}

sub _read_body_chunked {
    my ($self, $sock, $res_content, $rest_header, $timeout) = @_;

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
  READ_LOOP: while (!defined($res_content_length) || $res_content_length != $nread) {
        my $n = $self->read_timeout( $sock,
            \my $buf, $self->{bufsize}, 0, $timeout );
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
    while (1) {
        my($rfd, $wfd);
        my $efd = '';
        vec($efd, fileno($sock), 1) = 1;
        if ($is_write) {
            $wfd = $efd;
        } else {
            $rfd = $efd;
        }
        my $start_at = time;
        my $nfound   = select($rfd, $wfd, $efd, $timeout);
        return 1 if $nfound;
        $timeout    -= (time - $start_at);
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

# You can override this method if you want to use more powerful matcher.
sub match_no_proxy {
    my ( $self, $no_proxy, $host ) = @_;

    # ref. curl1.
    #   list of host names that shouldn't go through any proxy.
    #   If set to a asterisk '*' only, it matches all hosts.
    if ( $no_proxy eq '*' ) {
        return 1;
    }
    else {
        for my $pat ( split /\s*,\s*/, lc $no_proxy ) {
            if ( $host =~ /\Q$pat\E$/ ) { # suffix match(same behavior with LWP)
                return 1;
            }
        }
    }
    return 0;
}

# utility class
{
    package Furl::FileStream;
    use overload '.=' => 'append', fallback => 1;
    sub new {
        my ($class, $fh) = @_;
        bless {fh => $fh}, $class;
    }
    sub append {
        my($self, $partial) = @_;
        print {$self->{fh}} $partial;
        return $self;
    }
    sub get_response_string { undef }
}

{
    package Furl::CallbackStream;
    use overload '.=' => 'append', fallback => 1;
    sub new {
        my ($class, $cb) = @_;
        bless {cb => $cb}, $class;
    }
    sub append {
        my($self, $partial) = @_;
        $self->{cb}->($partial);
        return $self;
    }
    sub get_response_string { undef }
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
for weekend hacking. Furl resolves these issues. Enjoy it!

This library is an B<alpha> software. Any API may change without notice.

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

=item no_proxy :Str

=item headers :ArrayRef

=back

=head2 Instance Methods

=head3 C<< $furl->request(%args) :($code, $msg, \@headers, $body) >>

Sends an HTTP request to a specified URL and returns a status code,
status message, response headers, response body respectively.

I<%args> might be:

=over

=item scheme :Str = "http"

Protocol scheme. May be C<http> or C<https>.

=item host :Str

Server host to connect.

You must specify at least C<host> or C<url>.

=item port :Int = 80

Server port to connect. The default is 80 on C<< scheme => 'http' >>,
or 443 on C<< scheme => 'https' >>.

=item path_query :Str = "/"

Path and query to request.

=item url :Str

URL to request.

You can use C<url> instead of C<scheme>, C<host>, C<port> and C<path_query>.

=item headers :ArrayRef

HTTP request headers. e.g. C<< headers => [ 'Accept-Encoding' => 'gzip' ] >>.

=item content : Str | ArrayRef[Str] | HashRef[Str] | FileHandle

Content to request.

=back

You must encode all the queries or this method will die, saying
C<Wide character in ...>.

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

Loads proxy settings from C<< $ENV{HTTP_PROXY} >> and C<< $ENV{NO_PROXY} >>.

=head2 Utilities

=head3 C<< Furl::Util::header_get(\@headers, $name :Str) :Maybe[Str] >>

This is equivalent to C<< Plack::Util::header_get() >>.

=head1 INTEGRATE WITH HTTP::Response

Some useful libraries require HTTP::Response instances for their arguments.
You can easily create its instance from the result of C<request()> and other HTTP request methods.

    my $res = HTTP::Response->new($furl->get($url));

=head1 PROJECT POLICY

=over 4

=item Why IO::Socket::SSL?

Net::SSL is not well documented.

=item Why is env_proxy optional?

Environment variables are highly dependent on each users' environment,
and we think it may confuse users when something doesn't go right.

=item What operating systems are supported?

Linux 2.6 or higher, OSX Tiger or higher, Windows XP or higher.

And other operating systems will be supported if you send a patch.

=item Why doesn't Furl support chunked upload?

There are reasons why chunked POST/PUTs should not be used in general.

First, you cannot send chunked requests unless the peer server at the other end of the established TCP connection is known to be a HTTP/1.1 server.

Second, HTTP/1.1 servers disconnect their persistent connection quite quickly (compared to the time they wait for the first request), so it is not a good idea to post non-idempotent requests (e.g. POST, PUT, etc.) as a succeeding request over persistent connections.

These facts together makes using chunked requests virtually impossible (unless you _know_ that the server supports HTTP/1.1), and this is why we decided that supporting the feature is NOT of high priority.

=back

=head1 FAQ

=over 4

=item How do you build the response content as it arrives?

You can use L<IO::Callback> for this purpose.

    my $fh = IO::Callback->new(
        '<',
        sub {
            my $x = shift @data;
            $x ? "-$x" : undef;
        }
    );
    my ( $code, $msg, $headers, $content ) =
      $furl->put( "http://127.0.0.1:$port/", [ 'Content-Length' => $len ], $fh,
      );

=item How do you use cookie_jar?

Furl does not directly support the cookie_jar option available in LWP. You can use L<HTTP::Cookies>, L<HTTP::Request>, L<HTTP::Response> like following.

    my $f = Furl->new();
    my $cookies = HTTP::Cookies->new();
    my $req = HTTP::Request->new(...);
    $cookies->add_cookie_header($req);
    my $res = HTTP::Response->new($f->request_with_http_request($req));
    $cookies->extract_cookies($res);
    # and use $res.

=item How do you use gzip/deflate compressed communication?

Add an B<Accept-Encoding> header to your request. Furl inflates response bodies transparently according to the B<Content-Encoding> response header.

=item How do you use mutipart/form-data?

You can use multipart/form-data with L<HTTP::Request::Common>.

    use HTTP::Request::Common;

    my $furl = Furl->new();
    $req = POST 'http://www.perl.org/survey.cgi',
      Content_Type => 'form-data',
      Content      => [
        name   => 'Hiromu Tokunaga',
        email  => 'tokuhirom@example.com',
        gender => 'F',
        born   => '1978',
        init   => ["$ENV{HOME}/.profile"],
      ];
    $furl->request_with_http_request($req);

Native multipart/form-data support for L<Furl> is available if you can send a patch for me.

=item How do you use Keep-Alive and what happens on the HEAD method?

Furl supports HTTP/1.1, hence C<Keep-Alive>. However, if you use the HEAD
method, the connection is closed immediately.

RFC 2616 section 9.4 says:

    The HEAD method is identical to GET except that the server MUST NOT
    return a message-body in the response.

Some web applications, however, returns message bodies on the HEAD method,
which might confuse C<Keep-Alive> processes, so Furl closes connection in
such cases.

Anyway, the HEAD method is not so useful nowadays. The GET method and
C<If-Modified-Sinse> are more suitable to cache HTTP contents.

=back

=head1 TODO

    - AnyEvent::Furl?
    - use HTTP::Response::Parser
    - PP version(by HTTP::Respones::Parser)
    - ipv6 support
    - better docs for NO_PROXY

=head1 OPTIONAL FEATURES

=head2 Internationalized Domain Name (IDN)

This feature requires Net::IDN::Encode.

=head2 SSL

This feature requires IO::Socket::SSL.

=head2 Content-Encoding (deflate, gzip)

This feature requires Compress::Raw::Zlib.

=head1 DEVELOPMENT

To setup your environment:

    $ git clone http://github.com/tokuhirom/p5-Furl.git
    $ cd p5-Furl

To get picohttpparser:

    $ git submodule init
    $ git submodule update

    $ perl Makefile.PL
    $ make
    $ sudo make install

=head2 HOW TO CONTRIBUTE

Please send the pull-req via L<http://github.com/tokuhirom/p5-Furl/>.

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

Fuji, Goro (gfx)

=head1 THANKS TO

Kazuho Oku

mala

mattn

lestrrat

=head1 SEE ALSO

L<LWP>

HTTP specs:
L<http://www.w3.org/Protocols/HTTP/1.0/spec.html>
L<http://www.w3.org/Protocols/HTTP/1.1/spec.html>

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
