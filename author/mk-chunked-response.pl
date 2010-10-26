#!perl -w
use strict;
use Furl;
use Plack::Loader;
use Child;

{
    package Furl::Verbose;
    use parent qw(Furl);
    sub read_timeout {
        my $self = shift;
        my $ret  = $self->SUPER::read_timeout(@_);
        print ${$_[1]};
        return $ret;
    }
}

my $content = "The quick brown fox jumps over the lazy dog.\n" x 100;

my $child = Child->new(
    sub {
        Plack::Loader->load('Starman', host => '127.0.0.1', port => 1234 )
          ->run(
            sub { [ 200, ['Transfer-Encoding' => 'chunked' ], [$content] ] } );
    }
);
my $proc = $child->start();
sleep 1;
Furl::Verbose->new->get('http://127.0.0.1:1234/');
$proc->kill('TERM');

