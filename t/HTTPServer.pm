package t::HTTPServer;
use strict;
use warnings;
use IO::Socket::INET;
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use Carp ();

# taken from HTTP::Status
our %STATUS_CODE = (
    100 => 'Continue',
    101 => 'Switching Protocols',
    102 => 'Processing',                      # RFC 2518 (WebDAV)
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    207 => 'Multi-Status',                    # RFC 2518 (WebDAV)
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Timeout',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Large',
    415 => 'Unsupported Media Type',
    416 => 'Request Range Not Satisfiable',
    417 => 'Expectation Failed',
    422 => 'Unprocessable Entity',            # RFC 2518 (WebDAV)
    423 => 'Locked',                          # RFC 2518 (WebDAV)
    424 => 'Failed Dependency',               # RFC 2518 (WebDAV)
    425 => 'No code',                         # WebDAV Advanced Collections
    426 => 'Upgrade Required',                # RFC 2817
    449 => 'Retry with',                      # unofficial Microsoft
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
    506 => 'Variant Also Negotiates',         # RFC 2295
    507 => 'Insufficient Storage',            # RFC 2518 (WebDAV)
    509 => 'Bandwidth Limit Exceeded',        # unofficial
    510 => 'Not Extended',                    # RFC 2774
);

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    $args{port} || Carp::croak("missing mandatory parameter 'port'");
    bless {
        bufsize => 10*1024,
        protocol => "HTTP/1.1",
        enable_chunked => 1,
        %args
    }, $class;
}

sub add_trigger {
    my ($self, $name, $code) = @_;
    push @{$self->{triggers}->{$name}}, $code;
    return $self;
}

sub call_trigger {
    my ($self, $name, @args) = @_;
    for my $code (@{ $self->{triggers}->{$name} || +[] }) {
        $code->($self, @args);
    }
}

sub run {
    my ( $self, $app ) = @_;

    $app = $self->fill_content_length($app);

    local $SIG{PIPE} = "IGNORE";
    my $sock = IO::Socket::INET->new(
        Listen    => SOMAXCONN,
        Proto     => 'tcp',
        ReuseAddr => 1,
        LocalAddr => '127.0.0.1',
        LocalPort => $self->{port},
        Timeout   => 3,
    ) or die $!;
    $sock->autoflush(1);
    while ( my $csock = $sock->accept ) {
        $csock->setsockopt( IPPROTO_TCP, TCP_NODELAY, 1 )
          or die "setsockopt(TCP_NODELAY) failed:$!";
        eval {
            $self->handle_connection($csock => $app);
        };
        print STDERR "# $@" if $@;
    }
}

sub make_header {
    my ($self, $code, $headers) = @_;
    my $msg = $STATUS_CODE{$code} || $code;
    my $ret = "$self->{protocol} $code $msg\015\012";
    for (my $i=0; $i<@$headers; $i+=2) {
        $ret .= $headers->[$i] . ': ' . $headers->[$i+1] . "\015\012";
    }
    return $ret;
}

sub handle_connection {
    my ($self, $csock, $app) = @_;

    $self->call_trigger( "BEFORE_HANDLE_CONNECTION", $csock );
    HANDLE_LOOP: while (1) {
        $self->call_trigger( "BEFORE_HANDLE_REQUEST", $csock );
        my %env;
        my $buf = '';
      PARSE_HTTP_REQUEST: while (1) {
            my $nread = sysread( $csock, $buf, $self->{bufsize}, length($buf) );
            $buf =~ s!^(\015\012)*!! if defined($buf); # for keep-alive
            if ( !defined $nread ) {
                die "cannot read HTTP request header: $!";
            }
            if ( $nread == 0 ) {
                # unexpected EOF while reading HTTP request header
                last HANDLE_LOOP;
            }
            my $ret = parse_http_request( $buf, \%env );
            if ( $ret == -2 ) {    # incomplete.
                next;
            }
            elsif ( $ret == -1 ) {    # request is broken
                die "broken HTTP header";
            }
            else {
                $buf = substr( $buf, $ret );
                last PARSE_HTTP_REQUEST;
            }
        }
        my $res = $app->( \%env );
        my $res_header =
          $self->make_header( $res->[0], $res->[1] ) . "\015\012";
        $self->write_all( $csock, $res_header );
        for my $body (@{$res->[2]}) {
            $self->write_all( $csock, $body );
        }
        $self->call_trigger( "AFTER_HANDLE_REQUEST", $csock );
        last HANDLE_LOOP unless $csock->opened;
    }
    $self->call_trigger( "AFTER_HANDLE_CONNECTION", $csock );
}

sub fill_content_length {
    my ($self, $app) = @_;

    sub {
        my $env = shift;
        my $res = $app->($env);
        my $h = t::HTTPServer::Headers->new( $res->[1] );
        if (
            !t::HTTPServer::Util::status_with_no_entity_body( $res->[0] )
            && !$h->exists('Content-Length')
            && !$h->exists('Transfer-Encoding')
            && defined(
                my $content_length = t::HTTPServer::Util::content_length( $res->[2] )
            )
        ) {
            push @{$res->[1]}, 'Content-Length' => $content_length;
        }
        return $res;
    }
}

sub write_all {
    my ( $self, $csock, $buf ) = @_;
    my $off = 0;
    while ( my $len = length($buf) - $off ) {
        my $nwrite = $csock->syswrite( $buf, $len, $off )
            or die "Cannot write response: $!";
        $off += $nwrite;
    }
    return $off;
}

sub parse_http_request {
    my ( $chunk, $env ) = @_;
    Carp::croak("second param to parse_http_request should be a hashref")
      unless ( ref $env || '' ) eq 'HASH';

    # pre-header blank lines are allowed (RFC 2616 4.1)
    $chunk =~ s/^(\x0d?\x0a)+//;
    return -2 unless length $chunk;

    # double line break indicates end of header; parse it
    if ( $chunk =~ /^(.*?\x0d?\x0a\x0d?\x0a)/s ) {
        return _parse_header( $chunk, length $1, $env );
    }
    return -2;    # still waiting for unknown amount of header lines
}

sub _parse_header {
    my($chunk, $eoh, $env) = @_;

    my $header = substr($chunk, 0, $eoh,'');
    $chunk =~ s/^\x0d?\x0a\x0d?\x0a//;

    # parse into lines
    my @header  = split /\x0d?\x0a/,$header;
    my $request = shift @header;

    # join folded lines
    my @out;
    for(@header) {
        if(/^[ \t]+/) {
            return -1 unless @out;
            $out[-1] .= $_;
        } else {
            push @out, $_;
        }
    }

    # parse request or response line
    my $obj;
    my ($major, $minor);

    my ($method,$uri,$http) = split / /,$request;
    return -1 unless $http and $http =~ /^HTTP\/(\d+)\.(\d+)$/i;
    ($major, $minor) = ($1, $2);

    my($path, $query) = ( $uri =~ /^([^?]*)(?:\?(.*))?$/s );
    # following validations are just needed to pass t/01simple.t
    if ($path =~ /%(?:[0-9a-f][^0-9a-f]|[^0-9a-f][0-9a-f])/i) {
        # invalid char in url-encoded path
        return -1;
    }
    if ($path =~ /%(?:[0-9a-f])$/i) {
        # partially url-encoded
        return -1;
    }

    $env->{REQUEST_METHOD}  = $method;
    $env->{REQUEST_URI}     = $uri;
    $env->{SERVER_PROTOCOL} = "HTTP/$major.$minor";
    $env->{PATH_INFO}    = uri_unescape($path);
    $env->{QUERY_STRING} = $query || '';
    $env->{SCRIPT_NAME}  = '';

    # import headers
    my $token = qr/[^][\x00-\x1f\x7f()<>@,;:\\"\/?={} \t]+/;
    my $k;
    for my $header (@out) {
        if ( $header =~ s/^($token): ?// ) {
            $k = $1;
            $k =~ s/-/_/g;
            $k = uc $k;

            if ($k !~ /^(?:CONTENT_LENGTH|CONTENT_TYPE)$/) {
                $k = "HTTP_$k";
            }
        } elsif ( $header =~ /^\s+/) {
            # multiline header
        } else {
            return -1;
        }

        if (exists $env->{$k}) {
            $env->{$k} .= ", $header";
        } else {
            $env->{$k} = $header;
        }
    }

    return $eoh;
}

sub uri_unescape {
    local $_ = shift;
    $_ =~ s/%([0−9A−Fa−f]{2})/chr(hex($1))/eg;
    $_;
}

package t::HTTPServer::Util;
# code taken from Plack::Util.

use Scalar::Util ();

sub status_with_no_entity_body {
    my $status = shift;
    return $status < 200 || $status == 204 || $status == 304;
}

sub content_length {
    my $body = shift;

    return unless defined $body;

    if (ref $body eq 'ARRAY') {
        my $cl = 0;
        for my $chunk (@$body) {
            $cl += length $chunk;
        }
        return $cl;
    } elsif ( is_real_fh($body) ) {
        return (-s $body) - tell($body);
    }

    return;
}

sub is_real_fh ($) {
    my $fh = shift;

    my $reftype = Scalar::Util::reftype($fh) or return;
    if (   $reftype eq 'IO'
        or $reftype eq 'GLOB' && *{$fh}{IO}
    ) {
        # if it's a blessed glob make sure to not break encapsulation with
        # fileno($fh) (e.g. if you are filtering output then file descriptor
        # based operations might no longer be valid).
        # then ensure that the fileno *opcode* agrees too, that there is a
        # valid IO object inside $fh either directly or indirectly and that it
        # corresponds to a real file descriptor.
        my $m_fileno = $fh->fileno;
        return 0 unless defined $m_fileno;
        return 0 unless $m_fileno >= 0;

        my $f_fileno = fileno($fh);
        return 0 unless defined $f_fileno;
        return 0 unless $f_fileno >= 0;
        return 1;
    } else {
        # anything else, including GLOBS without IO (even if they are blessed)
        # and non GLOB objects that look like filehandle objects cannot have a
        # valid file descriptor in fileno($fh) context so may break.
        return 0;
    }
}

package t::HTTPServer::Headers;

sub new {
    my ($class, $headers) = @_;
    my %h;
    for (my $i=0; $i<@$headers; $i++) {
        my ($k, $v) = ($headers->[$i], $headers->[$i+1]);
        push @{$h{lc $k}}, $v;
    }
    return bless \%h, $class;
}

sub exists {
    my ($self, $key) = @_;
    $self->{lc $key} ? 1 : 0;
}

sub header {
    my ($self, $key) = @_;
    my $val = $self->{lc $key};
    return unless $val;
    return wantarray ? @$val : join(', ', @$val);
}

1;
