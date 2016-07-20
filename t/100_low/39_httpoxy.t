use strict;
use warnings;
use Furl::HTTP;
use Test::More;

plan tests => 8;

sub test_proxy {
  my $expect = shift;
  my $client = Furl::HTTP->new->env_proxy;
  $client->{proxy};
}

undef $ENV{REQUEST_METHOD};
undef $ENV{HTTP_PROXY};
undef $ENV{http_proxy};
is test_proxy, '';

$ENV{REQUEST_METHOD} = 'GET';
undef $ENV{HTTP_PROXY};
undef $ENV{http_proxy};
is test_proxy, '';

SKIP: {
    skip 'skip Windows', 1 if $^O eq 'MSWin32';
    undef $ENV{REQUEST_METHOD};
    $ENV{HTTP_PROXY} = 'http://proxy1.example.com';
    undef $ENV{http_proxy};
    is test_proxy, 'http://proxy1.example.com';
}

$ENV{REQUEST_METHOD} = 'GET';
$ENV{HTTP_PROXY} = 'http://proxy1.example.com';
undef $ENV{http_proxy};
is test_proxy, '';

undef $ENV{REQUEST_METHOD};
undef $ENV{HTTP_PROXY};
$ENV{http_proxy} = 'http://proxy2.example.com';
is test_proxy, 'http://proxy2.example.com';

SKIP: {
    skip 'skip Windows', 1 if $^O eq 'MSWin32';
    $ENV{REQUEST_METHOD} = 'GET';
    undef $ENV{HTTP_PROXY};
    $ENV{http_proxy} = 'http://proxy2.example.com';
    is test_proxy, 'http://proxy2.example.com';
}

undef $ENV{REQUEST_METHOD};
$ENV{HTTP_PROXY} = 'http://proxy1.example.com';
$ENV{http_proxy} = 'http://proxy2.example.com';
is test_proxy, 'http://proxy2.example.com';

SKIP: {
    skip 'skip Windows', 1 if $^O eq 'MSWin32';
    $ENV{REQUEST_METHOD} = 'GET';
    $ENV{HTTP_PROXY} = 'http://proxy1.example.com';
    $ENV{http_proxy} = 'http://proxy2.example.com';
    is test_proxy, 'http://proxy2.example.com';
}
