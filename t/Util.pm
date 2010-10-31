package t::Util;
use strict;
use warnings;
use base qw/Exporter/;
use Test::More;
use Furl::HTTP;
use Fcntl qw(O_CREAT O_RDWR SEEK_SET);

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
    # return the cache if exists
    sysopen my $cache, '.online', O_CREAT | O_RDWR
        or return 0;

    my $online = <$cache>;
    if(defined $online) {
        return $online; # cache
    }

    my $furl = Furl::HTTP->new(timeout => 5);
    my $good = 0;
    my $bad  = 0;
    note 'checking if online';
    $online = eval {
        for (my $i=0; $i<@RELIABLE_HTTP; $i+=2) {
            my ($url, $check) = @RELIABLE_HTTP[$i, $i+1];
            note "getting $url";
            my ($version, $code, $msg, $headers, $content)
                = $furl->request(url => $url);
            note "$code $msg";
            local $_ = $content;
            if ($code == 200 && $check->()) {
                $good++;
            } else {
                $bad++;
            }

            return 1 if $good > 1;
            return 0 if $bad  > 2;
        }
    };
    diag $@ if $@;

    seek $cache, 0, SEEK_SET;
    print $cache $online ? 1 : 0;
    close $cache;
    return $online;
}

sub skip_if_offline {
    plan skip_all => "This test requires online env" unless online();
}

1;
