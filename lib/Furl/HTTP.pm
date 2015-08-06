package Furl::HTTP;
use strict;
use warnings;
use base qw/Exporter/;
use 5.008001;

our $VERSION = '3.08';

use Carp ();
use Furl::ConnectionCache;

use Scalar::Util ();
use Errno qw(EAGAIN ECONNRESET EINPROGRESS EINTR EWOULDBLOCK ECONNABORTED EISCONN);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK SEEK_SET SEEK_END);
use Socket qw(
    PF_INET SOCK_STREAM
    IPPROTO_TCP
    TCP_NODELAY
    pack_sockaddr_in
);
use Time::HiRes qw(time);

use constant WIN32 => $^O eq 'MSWin32';
use HTTP::Parser::XS qw/HEADERS_NONE HEADERS_AS_ARRAYREF HEADERS_AS_HASHREF/;

our @EXPORT_OK = qw/HEADERS_NONE HEADERS_AS_ARRAYREF HEADERS_AS_HASHREF/;


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
        'User-Agent' => (delete($args{agent}) || __PACKAGE__ . '/' . $Furl::HTTP::VERSION),
    );
    my $connection_header = 'keep-alive';
    if(defined $args{headers}) {
        my $in_headers = delete $args{headers};
        for (my $i = 0; $i < @$in_headers; $i += 2) {
            my $name = $in_headers->[$i];
            if (lc($name) eq 'connection') {
                $connection_header = $in_headers->[$i + 1];
            } else {
                push @headers, $name, $in_headers->[$i + 1];
            }
        }
    }
    bless {
        timeout            => 10,
        max_redirects      => 7,
        bufsize            => 10*1024, # no mmap
        headers            => \@headers,
        connection_header  => $connection_header,
        proxy              => '',
        no_proxy           => '',
        connection_pool    => Furl::ConnectionCache->new(),
        header_format      => HEADERS_AS_ARRAYREF,
        stop_if            => sub {},
        inet_aton          => sub { Socket::inet_aton($_[0]) },
        ssl_opts           => {},
        capture_request    => $args{capture_request} || 0,
        inactivity_timeout => 600,
        %args
    }, $class;
}

sub get {
    my ( $self, $url, $headers ) = @_;
    $self->request(
        method  => 'GET',
        url     => $url,
        headers => $headers
    );
}

sub head {
    my ( $self, $url, $headers ) = @_;
    $self->request(
        method  => 'HEAD',
        url     => $url,
        headers => $headers
    );
}

sub post {
    my ( $self, $url, $headers, $content ) = @_;
    $self->request(
        method  => 'POST',
        url     => $url,
        headers => $headers,
        content => $content
    );
}

sub put {
    my ( $self, $url, $headers, $content ) = @_;
    $self->request(
        method  => 'PUT',
        url     => $url,
        headers => $headers,
        content => $content
    );
}

sub delete {
    my ( $self, $url, $headers, $content ) = @_;
    $self->request(
        method  => 'DELETE',
        url     => $url,
        headers => $headers,
        content => $content
    );
}

sub agent {
    if ( @_ == 2 ) {
        _header_set(shift->{headers}, 'User-Agent', shift);
    } else {
        return _header_get(shift->{headers}, 'User-Agent');
    }
}

sub _header_set {
    my ($headers, $key, $value) = (shift, lc shift, shift);
    for (my $i=0; $i<@$headers; $i+=2) {
        if (lc($headers->[$i]) eq $key) {
            $headers->[$i+1] = $value;
            return;
        }
    }
    push @$headers, $key, $value;
}

sub _header_get {
    my ($headers, $key) = (shift, lc shift);
    for (my $i=0; $i<@$headers; $i+=2) {
        return $headers->[$i+1] if lc($headers->[$i]) eq $key;
    }
    return undef;
}

sub _requires {
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

# returns $scheme, $host, $port, $path_query
sub _parse_url {
    my($self, $url) = @_;
    $url =~ m{\A
        ([a-z]+)                    # scheme
        ://
        (?:
            ([^/:@?]+) # user
            :
            ([^/:@?]+) # password
            @
        )?
        ([^/:?]+)                   # host
        (?: : (\d+) )?              # port
        (?: ( /? \? .* | / .*)  )?  # path_query
    \z}xms or Carp::croak("Passed malformed URL: $url");
    return( $1, $2, $3, $4, $5, $6 );
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

sub request {
    my $self = shift;
    my %args = @_;

    my $timeout_at = time + $self->{timeout};

    my ($scheme, $username, $password, $host, $port, $path_query);
    if (defined(my $url = $args{url})) {
        ($scheme, $username, $password, $host, $port, $path_query) = $self->_parse_url($url);
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

    my $default_port = $scheme eq 'http'
        ? 80
        : 443;
    if(not defined $port) {
        $port = $default_port;
    }
    if(not defined $path_query) {
        $path_query = '/';
    }

    unless (substr($path_query, 0, 1) eq '/') {
        $path_query = "/$path_query"; # Compensate for slash (?foo=bar => /?foo=bar)
    }

    # Note. '_' is a invalid character for URI, but some servers using fucking underscore for domain name. Then, I accept the '_' character for domain name.
    if ($host =~ /[^A-Za-z0-9._-]/) {
        _requires('Net/IDN/Encode.pm',
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
    my $sock         = $self->{connection_pool}->steal($host, $port);
    my $in_keepalive = defined $sock;
    if(!$in_keepalive) {
        my $err_reason;
        if ($proxy) {
            my (undef, $proxy_user, $proxy_pass, $proxy_host, $proxy_port, undef)
                = $self->_parse_url($proxy);
            my $proxy_authorization;
            if (defined $proxy_user) {
                _requires('MIME/Base64.pm',
                    'Basic auth');
                $proxy_authorization = 'Basic ' . MIME::Base64::encode_base64("$proxy_user:$proxy_pass","");
            }
            if ($scheme eq 'http') {
                ($sock, $err_reason)
                    = $self->connect($proxy_host, $proxy_port, $timeout_at);
                if (defined $proxy_authorization) {
                    $self->{proxy_authorization} = $proxy_authorization;
                }
            } else {
                ($sock, $err_reason) = $self->connect_ssl_over_proxy(
                    $proxy_host, $proxy_port, $host, $port, $timeout_at, $proxy_authorization);
            }
        } else {
            if ($scheme eq 'http') {
                ($sock, $err_reason)
                    = $self->connect($host, $port, $timeout_at);
            } else {
                ($sock, $err_reason)
                    = $self->connect_ssl($host, $port, $timeout_at);
            }
        }
        return $self->_r500($err_reason)
            unless $sock;
    }

    # keep request dump
    my ($req_headers, $req_content) = ("", "");

    # write request
    my $method = $args{method} || 'GET';
    my $connection_header = $self->{connection_header};
    my $cookie_jar = $self->{cookie_jar};
    {
        my @headers = @{$self->{headers}};
        $connection_header = 'close'
            if $method eq 'HEAD';
        if (my $in_headers = $args{headers}) {
            for (my $i = 0; $i < @$in_headers; $i += 2) {
                my $name = $in_headers->[$i];
                if (lc($name) eq 'connection') {
                    $connection_header = $in_headers->[$i + 1];
                } else {
                    push @headers, $name, $in_headers->[$i + 1];
                }
            }
        }
        unshift @headers, 'Connection', $connection_header;
        if (exists $self->{proxy_authorization}) {
            push @headers, 'Proxy-Authorization', $self->{proxy_authorization};
        }
        if (defined $username) {
            _requires('MIME/Base64.pm', 'Basic auth');
            push @headers, 'Authorization', 'Basic ' . MIME::Base64::encode_base64("${username}:${password}","");
        }

        # set Cookie header
        if (defined $cookie_jar) {
            my $url;
            if ($args{url}) {
                $url = $args{url};
            } else {
                $url = join(
                    '',
                    $args{scheme},
                    '://',
                    $args{host},
                    (exists($args{port}) ? ":$args{port}" : ()),
                    exists($args{path_query}) ? $args{path_query} : '/',
                );
            }
            push @headers, 'Cookie' => $cookie_jar->cookie_header($url);
        }

        my $content       = $args{content};
        my $content_is_fh = 0;
        if(defined $content) {
            $content_is_fh = Scalar::Util::openhandle($content);
            if(!$content_is_fh && ref $content) {
                $content = $self->make_x_www_form_urlencoded($content);
                if(!defined _header_get(\@headers, 'Content-Type')) {
                    push @headers, 'Content-Type'
                        => 'application/x-www-form-urlencoded';
                }
            }
            if(!defined _header_get(\@headers, 'Content-Length')) {
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

        # finally, set Host header
        my $request_target = ($port == $default_port) ? $host : "$host:$port";
        push @headers, 'Host' => $request_target;

        my $request_uri = $proxy && $scheme eq 'http' ? "$scheme://$request_target$path_query" : $path_query;

        my $p = "$method $request_uri HTTP/1.1\015\012";
        for (my $i = 0; $i < @headers; $i += 2) {
            my $val = $headers[ $i + 1 ];
            # the de facto standard way to handle [\015\012](by kazuho-san)
            $val =~ tr/\015\012/ /;
            $p .= "$headers[$i]: $val\015\012";
        }
        $p .= "\015\012";
        $self->write_all($sock, $p, $timeout_at)
            or return $self->_r500(
                "Failed to send HTTP request: " . _strerror_or_timeout());

        if ($self->{capture_request}) {
            $req_headers = $p;
        }

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
                    $self->write_all($sock, $buf, $timeout_at)
                        or return $self->_r500(
                            "Failed to send content: " . _strerror_or_timeout()
                        );

                    if ($self->{capture_request}) {
                        $req_content .= $buf;
                    }
                }
            } else { # simple string
                if (length($content) > 0) {
                    $self->write_all($sock, $content, $timeout_at)
                        or return $self->_r500(
                            "Failed to send content: " . _strerror_or_timeout()
                        );

                    if ($self->{capture_request}) {
                        $req_content = $content;
                    }
                }
            }
        }
    }

    # read response
    my $buf = '';
    my $rest_header;
    my $res_minor_version;
    my $res_status;
    my $res_msg;
    my $res_headers;
    my $special_headers = $args{special_headers} || +{};
    $special_headers->{'connection'}        = '';
    $special_headers->{'content-length'}    = undef;
    $special_headers->{'location'}          = '';
    $special_headers->{'content-encoding'}  = '';
    $special_headers->{'transfer-encoding'} = '';
  LOOP: while (1) {
        my $n = $self->read_timeout($sock,
            \$buf, $self->{bufsize}, length($buf), $timeout_at);
        if(!$n) { # error or eof
            if ($in_keepalive && length($buf) == 0
                && (defined($n) || $!==ECONNRESET || (WIN32 && $! == ECONNABORTED))) {
                # the server closes the connection (maybe because of keep-alive timeout)
                return $self->request(%args);
            }
            return $self->_r500(
                !defined($n)
                    ? "Cannot read response header: " . _strerror_or_timeout()
                    : "Unexpected EOF while reading response header"
            );
        }
        else {
            my $ret;
            ( $ret, $res_minor_version, $res_status, $res_msg, $res_headers )
                =  HTTP::Parser::XS::parse_http_response( $buf,
                       $self->{header_format}, $special_headers );
            if ( $ret == -1 ) {
                return $self->_r500("Invalid HTTP response");
            }
            elsif ( $ret == -2 ) {
                # partial response
                next LOOP;
            }
            else {
                # succeeded
                $rest_header = substr( $buf, $ret );
                last LOOP;
            }
        }
    }

    my $max_redirects = 0;
    my $do_redirect = undef;
    if ($special_headers->{location}) {
        $max_redirects = defined($args{max_redirects}) ? $args{max_redirects} : $self->{max_redirects};
        $do_redirect = $max_redirects && $res_status =~ /^30[1237]$/;
    }

    my $res_content = '';
    unless ($do_redirect) {
        if (my $fh = $args{write_file}) {
            $res_content = Furl::FileStream->new( $fh );
        } elsif (my $coderef = $args{write_code}) {
            $res_content = Furl::CallbackStream->new(
                sub { $coderef->($res_status, $res_msg, $res_headers, @_) }
            );
        }
    }

    if (exists $COMPRESSED{ $special_headers->{'content-encoding'} }) {
        _requires('Furl/ZlibStream.pm', 'Content-Encoding', 'Compress::Raw::Zlib');

        $res_content = Furl::ZlibStream->new($res_content);
    }

    my $chunked        = ($special_headers->{'transfer-encoding'} eq 'chunked');
    my $content_length =  $special_headers->{'content-length'};
    if (defined($content_length) && $content_length !~ /\A[0-9]+\z/) {
        return $self->_r500("Bad Content-Length: ${content_length}");
    }

    unless ($method eq 'HEAD'
            || ($res_status < 200 && $res_status >= 100)
            || $res_status == 204
            || $res_status == 304) {
        my @err;
        if ( $chunked ) {
            @err = $self->_read_body_chunked($sock,
                \$res_content, $rest_header, $timeout_at);
        } else {
            $res_content .= $rest_header;
            if (ref $res_content || !defined($content_length)) {
                @err = $self->_read_body_normal($sock,
                    \$res_content, length($rest_header),
                    $content_length, $timeout_at);
            } else {
                @err = $self->_read_body_normal_to_string_buffer($sock,
                    \$res_content, length($rest_header),
                    $content_length, $timeout_at);
            }
        }
        if(@err) {
            return @err;
        }
    }

    # manage connection cache (i.e. keep-alive)
    if (lc($connection_header) eq 'keep-alive') {
        my $connection = lc $special_headers->{'connection'};
        if (($res_minor_version == 0
             ? $connection eq 'keep-alive' # HTTP/1.0 needs explicit keep-alive
             : $connection ne 'close')    # HTTP/1.1 can keep alive by default
            && ( defined $content_length or $chunked)) {
            $self->{connection_pool}->push($host, $port, $sock);
        }
    }
    # explicitly close here, just after returning the socket to the pool,
    # since it might be reused in the upcoming recursive call
    undef $sock;

    # process 'Set-Cookie' header.
    if (defined $cookie_jar) {
        my $req_url = join(
            '',
            $scheme,
            '://',
            (defined($username) && defined($password) ? "${username}:${password}@" : ()),
            "$host:${port}${path_query}",
        );
        my $cookies = $res_headers->{'set-cookie'};
        $cookies = [$cookies] if !ref$cookies;
        for my $cookie (@$cookies) {
            $cookie_jar->add($req_url, $cookie);
        }
    }

    if ($do_redirect) {
        my $location = $special_headers->{location};
        unless ($location =~ m{^[a-z0-9]+://}) {
            # RFC 2616 14.30 says Location header is absolute URI.
            # But, a lot of servers return relative URI.
            _requires("URI.pm", "redirect with relative url");
            $location = URI->new_abs($location, "$scheme://$host:$port$path_query")->as_string;
        }
        # Note: RFC 1945 and RFC 2068 specify that the client is not allowed
        # to change the method on the redirected request.  However, most
        # existing user agent implementations treat 302 as if it were a 303
        # response, performing a GET on the Location field-value regardless
        # of the original request method. The status codes 303 and 307 have
        # been added for servers that wish to make unambiguously clear which
        # kind of reaction is expected of the client.
        return $self->request(
            @_,
            method        => ($res_status eq '301' or $res_status eq '307') ? $method : 'GET',
            url           => $location,
            max_redirects => $max_redirects - 1,
        );
    }

    # return response.

    if (ref $res_content) {
        $res_content = $res_content->get_response_string;
    }

    return (
        $res_minor_version, $res_status, $res_msg, $res_headers, $res_content,
        $req_headers, $req_content, undef, undef, [$scheme, $username, $password, $host, $port, $path_query],
    );
}

# connects to $host:$port and returns $socket
sub connect :method {
    my($self, $host, $port, $timeout_at) = @_;
    my $sock;

    my $timeout = $timeout_at - time;
    return (undef, "Failed to resolve host name: timeout")
        if $timeout <= 0;
    my ($sock_addr, $err_reason) = $self->_get_address($host, $port, $timeout);
    return (undef, "Cannot resolve host name: $host (port: $port), " . ($err_reason || $!))
        unless $sock_addr;

 RETRY:
    socket($sock, Socket::sockaddr_family($sock_addr), SOCK_STREAM, 0)
        or Carp::croak("Cannot create socket: $!");
    _set_sockopts($sock);
    if (connect($sock, $sock_addr)) {
        # connected
    } elsif ($! == EINPROGRESS || (WIN32 && $! == EWOULDBLOCK)) {
        $self->do_select(1, $sock, $timeout_at)
            or return (undef, "Cannot connect to ${host}:${port}: timeout");
        # connected
    } else {
        if ($! == EINTR && ! $self->{stop_if}->()) {
            close $sock;
            goto RETRY;
        }
        return (undef, "Cannot connect to ${host}:${port}: $!");
    }
    $sock;
}

sub _get_address {
    my ($self, $host, $port, $timeout) = @_;
    if ($self->{get_address}) {
        return $self->{get_address}->($host, $port, $timeout);
    }
    # default rule (TODO add support for IPv6)
    my $iaddr = $self->{inet_aton}->($host, $timeout)
        or return (undef, $!);
    pack_sockaddr_in($port, $iaddr);
}

sub _ssl_opts {
    my $self = shift;
    my $ssl_opts = $self->{ssl_opts};
    unless (exists $ssl_opts->{SSL_verify_mode}) {
        # set SSL_VERIFY_PEER as default.
        $ssl_opts->{SSL_verify_mode}     = IO::Socket::SSL::SSL_VERIFY_PEER();
        unless (exists $ssl_opts->{SSL_verifycn_scheme}) {
            $ssl_opts->{SSL_verifycn_scheme} = 'www'
        }
    }
    if ($ssl_opts->{SSL_verify_mode}) {
        unless (exists $ssl_opts->{SSL_ca_file} || exists $ssl_opts->{SSL_ca_path}) {
            require Mozilla::CA;
            $ssl_opts->{SSL_ca_file} = Mozilla::CA::SSL_ca_file();
        }
    }
    $ssl_opts;
}

# connect SSL socket.
# You can override this method in your child class, if you want to use Crypt::SSLeay or some other library.
# @return file handle like object
sub connect_ssl {
    my ($self, $host, $port, $timeout_at) = @_;
    _requires('IO/Socket/SSL.pm', 'SSL');

    my ($sock, $err_reason) = $self->connect($host, $port, $timeout_at);
    return (undef, $err_reason)
        unless $sock;

    my $timeout = $timeout_at - time;
    return (undef, "Cannot create SSL connection: timeout")
        if $timeout <= 0;

    my $ssl_opts = $self->_ssl_opts;
    IO::Socket::SSL->start_SSL(
        $sock,
        PeerHost => $host,
        PeerPort => $port,
        Timeout  => $timeout,
        %$ssl_opts,
    ) or return (undef, "Cannot create SSL connection: " . IO::Socket::SSL::errstr());
    _set_sockopts($sock);
    $sock;
}

sub connect_ssl_over_proxy {
    my ($self, $proxy_host, $proxy_port, $host, $port, $timeout_at, $proxy_authorization) = @_;
    _requires('IO/Socket/SSL.pm', 'SSL');

    my $sock = $self->connect($proxy_host, $proxy_port, $timeout_at);

    my $p = "CONNECT $host:$port HTTP/1.0\015\012Server: $host\015\012";
    if (defined $proxy_authorization) {
        $p .= "Proxy-Authorization: $proxy_authorization\015\012";
    }
    $p .= "\015\012";
    $self->write_all($sock, $p, $timeout_at)
        or return $self->_r500(
            "Failed to send HTTP request to proxy: " . _strerror_or_timeout());
    my $buf = '';
    my $read = $self->read_timeout($sock,
        \$buf, $self->{bufsize}, length($buf), $timeout_at);
    if (not defined $read) {
        return (undef, "Cannot read proxy response: " . _strerror_or_timeout());
    } elsif ( $read == 0 ) {    # eof
        return (undef, "Unexpected EOF while reading proxy response");
    } elsif ( $buf !~ /^HTTP\/1\.[0-9] 200 .+\015\012/ ) {
        return (undef, "Invalid HTTP Response via proxy");
    }

    my $timeout = $timeout_at - time;
    return (undef, "Cannot start SSL connection: timeout")
        if $timeout_at <= 0;

    my $ssl_opts = $self->_ssl_opts;
    unless (exists $ssl_opts->{SSL_verifycn_name}) {
        $ssl_opts->{SSL_verifycn_name} = $host;
    }
    IO::Socket::SSL->start_SSL(
        $sock,
        PeerHost => $host,
        PeerPort => $port,
        Timeout  => $timeout,
        %$ssl_opts
    ) or return (undef, "Cannot start SSL connection: " . IO::Socket::SSL::errstr());
    _set_sockopts($sock); # just in case (20101118 kazuho)
    $sock;
}

sub _read_body_chunked {
    my ($self, $sock, $res_content, $rest_header, $timeout_at) = @_;

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
                        )*               # optional chunk-extensions
                        [ ]*             # www.yahoo.com adds spaces here.
                                         # Is this valid?
                        \015\012         # CR+LF
                  ) }xmso
            )
          )
        {
            $buf = substr($buf, length($header)); # remove header from buf
            $next_len = hex($next_len);
            if ($next_len == 0) {
                last READ_LOOP;
            }

            # +2 means trailing CRLF
          READ_CHUNK: while ( $next_len+2 > length($buf) ) {
                my $n = $self->read_timeout( $sock,
                    \$buf, $self->{bufsize}, length($buf), $timeout_at );
                if (!$n) {
                    return $self->_r500(
                        !defined($n)
                            ? "Cannot read chunk: " . _strerror_or_timeout()
                            : "Unexpected EOF while reading packets"
                    );
                }
            }
            $$res_content .= substr($buf, 0, $next_len);
            $buf = substr($buf, $next_len+2);
            if (length($buf) > 0) {
                next; # re-parse header
            }
        }

        my $n = $self->read_timeout( $sock,
            \$buf, $self->{bufsize}, length($buf), $timeout_at );
        if (!$n) {
            return $self->_r500(
                !defined($n)
                    ? "Cannot read chunk: " . _strerror_or_timeout()
                    : "Unexpected EOF while reading packets"
            );
        }
    }
    # read last CRLF
    return $self->_read_body_normal(
        $sock, \$buf, length($buf), 2, $timeout_at);
}

sub _read_body_normal {
    my ($self, $sock, $res_content, $nread, $res_content_length, $timeout_at)
        = @_;
    while (!defined($res_content_length) || $res_content_length != $nread) {
        my $n = $self->read_timeout( $sock,
            \my $buf, $self->{bufsize}, 0, $timeout_at );
        if (!$n) {
            last if ! defined($res_content_length);
            return $self->_r500(
                !defined($n)
                    ? "Cannot read content body: " . _strerror_or_timeout()
                    : "Unexpected EOF while reading content body"
            );
        }
        $$res_content .= $buf;
        $nread        += $n;
    }
    return;
}

# This function loads all content at once if it's possible. Since $res_content is just a plain scalar.
# Buffering is not needed.
sub _read_body_normal_to_string_buffer {
    my ($self, $sock, $res_content, $nread, $res_content_length, $timeout_at)
        = @_;
    while ($res_content_length != $nread) {
        my $n = $self->read_timeout( $sock,
            $res_content, $res_content_length, $nread, $timeout_at );
        if (!$n) {
            return $self->_r500(
                !defined($n)
                    ? "Cannot read content body: " . _strerror_or_timeout()
                    : "Unexpected EOF while reading content body"
            );
        }
        $nread += $n;
    }
    return;
}

# returns true if the socket is ready to read, false if timeout has occurred ($! will be cleared upon timeout)
sub do_select {
    my($self, $is_write, $sock, $timeout_at) = @_;
    my $now = time;
    my $inactivity_timeout_at = $now + $self->{inactivity_timeout};
    $timeout_at = $inactivity_timeout_at
        if $timeout_at > $inactivity_timeout_at;
    # wait for data
    while (1) {
        my $timeout = $timeout_at - $now;
        if ($timeout <= 0) {
            $! = 0;
            return 0;
        }
        my($rfd, $wfd);
        my $efd = '';
        vec($efd, fileno($sock), 1) = 1;
        if ($is_write) {
            $wfd = $efd;
        } else {
            $rfd = $efd;
        }
        my $nfound   = select($rfd, $wfd, $efd, $timeout);
        return 1 if $nfound > 0;
        return 0 if $nfound == -1 && $! == EINTR && $self->{stop_if}->();
        $now = time;
    }
    die 'not reached';
}

# returns (positive) number of bytes read, or undef if the socket is to be closed
sub read_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout_at) = @_;
    my $ret;

    # NOTE: select-read-select may get stuck in SSL,
    #       so we use read-select-read instead.
    while(1) {
        # try to do the IO
        defined($ret = sysread($sock, $$buf, $len, $off))
            and return $ret;
        if ($! == EAGAIN || $! == EWOULDBLOCK || (WIN32 && $! == EISCONN)) {
            # passthru
        } elsif ($! == EINTR) {
            return undef if $self->{stop_if}->();
            # otherwise passthru
        } else {
            return undef;
        }
        # on EINTER/EAGAIN/EWOULDBLOCK
        $self->do_select(0, $sock, $timeout_at) or return undef;
    }
}

# returns (positive) number of bytes written, or undef if the socket is to be closed
sub write_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout_at) = @_;
    my $ret;
    while(1) {
        # try to do the IO
        defined($ret = syswrite($sock, $buf, $len, $off))
            and return $ret;
        if ($! == EAGAIN || $! == EWOULDBLOCK || (WIN32 && $! == EISCONN)) {
            # passthru
        } elsif ($! == EINTR) {
            return undef if $self->{stop_if}->();
            # otherwise passthru
        } else {
            return undef;
        }
        $self->do_select(1, $sock, $timeout_at) or return undef;
    }
}

# writes all data in buf and returns number of bytes written or undef if failed
sub write_all {
    my ($self, $sock, $buf, $timeout_at) = @_;
    my $off = 0;
    while (my $len = length($buf) - $off) {
        my $ret = $self->write_timeout($sock, $buf, $len, $off, $timeout_at)
            or return undef;
        $off += $ret;
    }
    return $off;
}


sub _r500 {
    my($self, $message) = @_;
    $message = Carp::shortmess($message); # add lineno and filename
    return(0, 500, "Internal Response: $message",
        [
            'Content-Length' => length($message),
            'X-Internal-Response' => 1,
            # XXX ^^ EXPERIMENTAL header. Do not depend to this.
        ], $message
    );
}

sub _strerror_or_timeout {
    $! != 0 ? "$!" : 'timeout';
}

sub _set_sockopts {
    my $sock = shift;

    setsockopt( $sock, IPPROTO_TCP, TCP_NODELAY, 1 )
        or Carp::croak("Failed to setsockopt(TCP_NODELAY): $!");
    if (WIN32) {
        if (ref($sock) ne 'IO::Socket::SSL') {
            my $tmp = 1;
            ioctl( $sock, 0x8004667E, \$tmp )
                or Carp::croak("Cannot set flags for the socket: $!");
        }
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

# You can override this method if you want to use more powerful matcher.
sub match_no_proxy {
    my ( $self, $no_proxy, $host ) = @_;

    # ref. curl.1.
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
    package # hide from pause
        Furl::FileStream;
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
    package # hide from pause
        Furl::CallbackStream;
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

=for stopwords sockaddr

=encoding utf8

=head1 NAME

Furl::HTTP - Low level interface to Furl

=head1 SYNOPSIS

    use Furl;

    my $furl = Furl::HTTP->new(
        agent   => 'MyGreatUA/2.0',
        timeout => 10,
    );

    my ($minor_version, $code, $msg, $headers, $body) = $furl->request(
        method     => 'GET',
        host       => 'example.com',
        port       => 80,
        path_query => '/'
    );
    # or

    # Accept-Encoding is supported but optional
    $furl = Furl->new(
        headers => [ 'Accept-Encoding' => 'gzip' ],
    );
    my $body = $furl->get('http://example.com/some/compressed');

=head1 DESCRIPTION

Furl is yet another HTTP client library. LWP is the de facto standard HTTP
client for Perl 5, but it is too slow for some critical jobs, and too complex
for weekend hacking. Furl resolves these issues. Enjoy it!

=head1 INTERFACE

=head2 Class Methods

=head3 C<< Furl::HTTP->new(%args | \%args) :Furl >>

Creates and returns a new Furl client with I<%args>. Dies on errors.

I<%args> might be:

=over

=item agent :Str = "Furl/$VERSION"

=item timeout :Int = 10

Seconds until the call to $furl->request returns a timeout error (as an internally generated 500 error). The timeout might not be accurate since some underlying modules / built-ins function may block longer than the specified timeout. See the FAQ for how to support timeout during name resolution.

=item inactivity_timeout :Int = 600

An inactivity timer for TCP read/write (in seconds). $furl->request returns a timeout error if no additional data arrives (or is sent) within the specified threshold.

=item max_redirects :Int = 7

=item proxy :Str

=item no_proxy :Str

=item headers :ArrayRef

=item header_format :Int = HEADERS_AS_ARRAYREF

This option choose return value format of C<< $furl->request >>.

This option allows HEADERS_NONE or HEADERS_AS_ARRAYREF.

B<HEADERS_AS_ARRAYREF> is a default value. This makes B<$headers> as ArrayRef.

B<HEADERS_NONE> makes B<$headers> as undef. Furl does not return parsing result of headers. You should take needed headers from B<special_headers>.

=item connection_pool :Object

This is the connection pool object for keep-alive requests. By default, it is a instance of L<Furl::ConnectionCache>.

You may not customize this variable otherwise to use L<Coro>. This attribute requires a duck type object. It has two methods, C<< $obj->steal($host, $port >> and C<< $obj->push($host, $port, $sock) >>.

=item stop_if :CodeRef

A callback function that is called by Furl after when a blocking function call returns EINTR. Furl will abort the HTTP request and return immediately if the callback returns true. Otherwise the operation is continued (the default behaviour).

=item get_address :CodeRef

A callback function to override the default address resolution logic. Takes three arguments: ($hostname, $port, $timeout_in_seconds) and returns: ($sockaddr, $errReason).  If the returned $sockaddr is undef, then the resolution is considered as a failure and $errReason is propagated to the caller.

=item inet_aton :CodeRef

Deprecated.  New applications should use B<get_address> instead.

A callback function to customize name resolution. Takes two arguments: ($hostname, $timeout_in_seconds). If omitted, Furl calls L<Socket::inet_aton>.

=item ssl_opts :HashRef

SSL configuration used on https requests, passed directly to C<< IO::Socket::SSL->new() >>,

for example:

    use IO::Socket::SSL;

    my $ua = Furl::HTTP->new(
        ssl_opts => {
            SSL_verify_mode => SSL_VERIFY_PEER(),
        },
    });

See L<IO::Socket::SSL> for details.

=back

=head2 Instance Methods

=head3 C<< $furl->request(%args) :($protocol_minor_version, $code, $msg, \@headers, $body) >>

Sends an HTTP request to a specified URL and returns a protocol minor version,
status code, status message, response headers, response body respectively.

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

=item write_file : FileHandle

If this parameter is set, the response content will be saved here instead of in the response object.

It's like a C<:content_file> in L<LWP::UserAgent>.

=item write_code : CodeRef

If a callback is provided with the "write_code" option
then this function will be called for each chunk of the response
content as it is received from the server.

It's like a C<:content_cb> in L<LWP::UserAgent>.

=back

The C<request()> method assumes the first argument to be an instance
of C<HTTP::Request> if the arguments are an odd number:

    my $req = HTTP::Request->new(...);
    my @res = $furl->request($req); # allowed

You must encode all the queries or this method will die, saying
C<Wide character in ...>.

=head3 C<< $furl->get($url :Str, $headers :ArrayRef[Str] ) >>

This is an easy-to-use alias to C<request()>, sending the C<GET> method.

=head3 C<< $furl->head($url :Str, $headers :ArrayRef[Str] ) >>

This is an easy-to-use alias to C<request()>, sending the C<HEAD> method.

=head3 C<< $furl->post($url :Str, $headers :ArrayRef[Str], $content :Any) >>

This is an easy-to-use alias to C<request()>, sending the C<POST> method.

=head3 C<< $furl->put($url :Str, $headers :ArrayRef[Str], $content :Any) >>

This is an easy-to-use alias to C<request()>, sending the C<PUT> method.

=head3 C<< $furl->delete($url :Str, $headers :ArrayRef[Str] ) >>

This is an easy-to-use alias to C<request()>, sending the C<DELETE> method.

=head1 FAQ

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

=item How do you use gzip/deflate compressed communication?

Add an B<Accept-Encoding> header to your request. Furl inflates response bodies transparently according to the B<Content-Encoding> response header.

=item How do you use multipart/form-data?

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
    $furl->request($req);

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

=item Why does Furl take longer than specified until it returns a timeout error?

Although Furl itself supports timeout, some underlying modules / functions do not. And the most noticeable one is L<Socket::inet_aton>, the function used for name resolution (a function that converts host names to IP addresses). If you need accurate and short timeout for name resolution, the use of L<Net::DNS::Lite> is recommended. The following code snippet describes how to use the module in conjunction with Furl.

    use Net::DNS::Lite qw();

    my $furl = Furl->new(
        timeout   => $my_timeout_in_seconds,
        inet_aton => sub { Net::DNS::Lite::inet_aton(@_) },
    );

=item How can I replace Host header instead of hostname?

Furl::HTTP does not provide a way to replace the Host header because such a design leads to security issues.

If you want to send HTTP requests to a dedicated server (or a UNIX socket), you should use the B<get_address> callback to designate the peer to which L<Furl> should connect as B<sockaddr>.

The example below sends all requests to 127.0.0.1:8080.

    my $ua = Furl::HTTP->new(
        get_address => sub {
            my ($host, $port, $timeout) = @_;
            pack_sockaddr_in(8080, inet_aton("127.0.0.1"));
        },
    );

    my ($minor_version, $code, $msg, $headers, $body) = $furl->request(
        url => 'http://example.com/foo',
        method => 'GET'
    );

=back

=head1 TODO

    - AnyEvent::Furl?
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

Please send the pull request via L<http://github.com/tokuhirom/p5-Furl/>.

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
