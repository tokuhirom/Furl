use strict;
use warnings;
use Socket qw(inet_aton pack_sockaddr_in);
use Test::More;
use Test::TCP;
use Test::Requires qw(HTTP::Server::PSGI);

use Furl::HTTP;
use FindBin;
use lib "$FindBin::Bin/../..";
use t::Slowloris;

test_tcp(
	server => sub {
		my $port = shift;
		$Slowloris::SleepBeforeWrite = 1;
		Slowloris::Server->new(port => $port)->run(sub {
			my $env = shift;
			return [ 200,
				[],
				[ "hello" ]
			];
		});
	},
	client => sub {
		my $port = shift;

		# should not timeout
		my $furl = Furl::HTTP->new(
			timeout => 10,
			inactivity_timeout => 10,
		);
		my $start = time;
		my ($minor_version, $code, $msg, $headers, $body) = $furl->request(
			method     => "GET",
			host       => "127.0.0.1",
			port       => $port,
			path_query => "/",
		);
		is $code, 200, "status code:inactivity_timeout=10";
		is $body, "hello", "content:inactivity_timeout=10";
		diag "took @{[time - $start]} seconds";

		# should timeout
		$furl = Furl::HTTP->new(
			timeout            => 10,
			inactivity_timeout => 0.5,
		);
		$start = time;
		($minor_version, $code, $msg, $headers, $body) = $furl->request(
			method     => "GET",
			host       => "127.0.0.1",
			port       => $port,
			path_query => "/",
		);
		is $code, 500, "status code:inactivity_timeout=0.5";
		diag "took @{[time - $start]} seconds";
	},
);

done_testing;
