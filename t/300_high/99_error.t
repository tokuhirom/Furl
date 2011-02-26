use strict;
use warnings;
use Furl;
use Test::More;
use File::Basename qw/basename/;

my $furl = Furl->new;
my $file_name = basename $0;

sub test_error_message (&) {
    my $code = shift;
    local $@;
    eval { $code->() };
    like $@, qr/$file_name/;
}

test_error_message { $furl->get('ttp://example.com/') };
test_error_message { $furl->head('ttp://example.com/') };
test_error_message { $furl->post('ttp://example.com/') };
test_error_message { $furl->delete('ttp://example.com/') };
test_error_message { $furl->put('ttp://example.com/') };
test_error_message {
    $furl->request(
        method => 'GET',
        url    => 'ttp://example.com/',
    );
};

done_testing;
