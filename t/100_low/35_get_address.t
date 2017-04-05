use strict;
use warnings;
use Socket qw(inet_aton pack_sockaddr_in);
use Test::More;
use Test::TCP;

use Furl::HTTP;
use FindBin;
use lib "$FindBin::Bin/../..";
use t::HTTPServer;

test_tcp(
	client => sub {
		my $serverPort = shift;
		my $furl = Furl::HTTP->new(
			get_address => sub {
				my ($host, $port, $timeout) = @_;
				is $host, "nowhere.example.com", "get_address:hostname";
				is $port, 80, "get_address:port";
				return pack_sockaddr_in($serverPort, inet_aton("127.0.0.1"));
			},
		);
		my ($minor_version, $code, $msg, $headers, $body) = $furl->request(
			method     => "GET",
			host       => "nowhere.example.com",
			port       => 80,
			path_query => "/abc",
		);
		is $code, 200, "status code";
		is $body, "hello furl", "content";
	},
	server => sub {
		my $port = shift;
		ok "yes";
		t::HTTPServer->new(port => $port)->run(sub {
			my $env = shift;
			return [ 200,
				[],
				[ "hello furl" ]
			];
		});
	}
);

done_testing;
