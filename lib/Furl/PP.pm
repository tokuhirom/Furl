package Furl::PP;
use strict;
use warnings;

# @return -1: invalid
#         -2: incomplete
#         >0: header length
sub Furl::parse_http_response {
    my ($buf, $last_len, $headers, $special_headers) = @_;
    return (-2) unless $buf =~ s{\A(.*?)\015\012}{};
    my $status_line = $1;
    my ($minor_version, $status, $msg) = $status_line =~ m{\AHTTP/1\.([01])[ ]+([0-9]{3})[ ]+(.+)\z};
    return (-1) unless defined($minor_version) && defined($status) && defined($msg);

    my $ret = length($status_line) + 2;
    while ($buf =~ s{\A(.*?)\015\012}{}) {
        my $header_line = $1;
        $ret += length($header_line) + 2;
        if ($header_line eq '') {
            return ($ret, $minor_version, $status, $msg);
        }
        if ($header_line =~ /\A\s/) {
            next; # ignore multiline header
        }

        my ($key, $val) = split /\s*:\s*/, $header_line, 2;
        push @$headers, lc($key), $val;
        if (exists $special_headers->{lc $key}) {
            $special_headers->{lc $key} = $val;
        }
    }

    return (-2); # incomplete
}

1;
