package t::Util;
use strict;
use warnings;
use base qw/Exporter/;
use Test::More;
use Furl;

our @EXPORT = qw/online skip_if_offline/;

my $orig = \&Furl::new;
sub wrapped_env_proxy {
    my ($class, %args) = @_;
    $args{proxy} = $ENV{HTTP_PROXY} if ($args{url}||'') !~ /^https?:\/\/\d+/;
    return $orig->($class, %args);
};
{
    no strict 'refs';
    no warnings 'redefine';
    *Furl::new = \&wrapped_env_proxy if $ENV{TEST_ENV_PROXY};
}

# taken from LWP::Online
my @RELIABLE_HTTP = (
    # These are some initial trivial checks.
    # The regex are case-sensitive to at least
    # deal with the "couldn't get site.com case".
    'http://google.com/' => sub { /About Google/      },
    'http://yahoo.com/'  => sub { /Yahoo!/            },
    'http://amazon.com/' => sub { /Amazon/ and /Cart/ },
    'http://cnn.com/'    => sub { /CNN/               },
);

sub online () {
    my $furl = Furl->new(timeout => 10);
    my $good = 0;
    my $bad  = 0;
    for (my $i=0; $i<@RELIABLE_HTTP; $i+=2) {
        my ($url, $check) = @RELIABLE_HTTP[$i, $i+1];
        note "getting $url";
        my ($code, $headers, $content) = $furl->request(method => 'GET', url => $url);
        note "OK $code";
        local $_ = $content;
        if ($code == 200 && $check->()) {
            $good++;
        } else {
            $bad++;
        }
        
        return 1 if $good > 1;
        return 0 if $bad  > 2;
    }
    return 0;
}

sub skip_if_offline {
    plan skip_all => "This test requires online env" unless online();
}

1;
