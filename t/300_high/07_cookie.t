use strict;
use warnings;
use utf8;
use Test::More;
use Test::Requires 'HTTP::CookieJar', 'Plack::Request', 'Plack::Loader', 'Plack::Builder', 'Plack::Response';
use Test::TCP;
use Furl;

subtest 'Simple case', sub {
    test_tcp(
        client => sub {
            my $port = shift;
            my $furl = Furl->new(
                cookie_jar => HTTP::CookieJar->new()
            );
            my $url = "http://127.0.0.1:$port";

            subtest 'first time access', sub {
                my $res = $furl->get("${url}/");

                note "Then, response should be 200 OK";
                is $res->status, 200;
                note "And, content should be 'OK 1'";
                is $res->content, 'OK 1';
            };

            subtest 'Second time access', sub {
                my $res = $furl->get("${url}/");

                note "Then, response should be 200 OK";
                is $res->status, 200;
                note "And, content should be 'OK 2'";
                is $res->content, 'OK 2';
            };
        },
        server => \&session_server,
    );
};

subtest '->request(host => ...) style simple interface', sub {
    test_tcp(
        client => sub {
            my $port = shift;
            my $furl = Furl->new(
                cookie_jar => HTTP::CookieJar->new()
            );

            subtest 'first time access', sub {
                my $res = $furl->request(
                    method => 'GET',
                    scheme => 'http',
                    host => '127.0.0.1',
                    port => $port,
                );

                note "Then, response should be 200 OK";
                is $res->status, 200;
                note "And, content should be 'OK 1'";
                is $res->content, 'OK 1';
            };

            subtest 'Second time access', sub {
                my $res = $furl->request(
                    method => 'GET',
                    scheme => 'http',
                    host => '127.0.0.1',
                    port => $port,
                );

                note "Then, response should be 200 OK";
                is $res->status, 200;
                note "And, content should be 'OK 2'";
                is $res->content, 'OK 2';
            };
        },
        server => \&session_server,
    );
};

subtest 'With redirect', sub {
    test_tcp(
        client => sub {
            my $port = shift;
            my $furl = Furl->new(
                cookie_jar => HTTP::CookieJar->new()
            );
            my $url = "http://127.0.0.1:$port";

            subtest 'first time access', sub {
                my $res = $furl->get("${url}/login");

                note "Then, response should be 200 OK";
                is $res->status, 200;
                note "And, content should be 'ok'";
                is $res->content, 'ok';
            };

            subtest 'Second time access', sub {
                my $res = $furl->get("${url}/user_name");

                note "Then, response should be 200 OK";
                is $res->status, 200;
                note "And, content should be 'Nick'";
                is $res->content, 'Nick';
            };
        },
        server => sub {
            my $port = shift;
            my %SESSION_STORE;
            Plack::Loader->auto( port => $port )->run(builder {
                enable 'ContentLength';
                enable 'StackTrace';

                sub {
                    my $env     = shift;
                    my $req = Plack::Request->new($env);
                    my $path_info = $env->{PATH_INFO};
                    $path_info =~ s!^//!/!;
                    if ($path_info eq '/login') {
                        my $res = Plack::Response->new(
                            302, ['Location' => $req->uri_for('/login_done')], []
                        );
                        $res->cookies->{'user_name'} = 'Nick';
                        return $res->finalize;
                    } elsif ($path_info eq '/login_done') {
                        my $res = Plack::Response->new(
                            200, [], ['ok']
                        );
                        return $res->finalize;
                    } elsif ($path_info eq '/user_name') {
                        my $res = Plack::Response->new(
                            200, [], [$req->cookies->{'user_name'}]
                        );
                        return $res->finalize;
                    } else {
                        my $res = Plack::Response->new(
                            404, [], ['not found:' . $env->{PATH_INFO}]
                        );
                        return $res->finalize;
                    }
                };
            });
        }
    );
};

done_testing;

sub session_server {
    my $port = shift;
    my %SESSION_STORE;
    Plack::Loader->auto( port => $port )->run(builder {
        enable 'ContentLength';

        sub {
            my $env     = shift;
            my $req = Plack::Request->new($env);
            my $session_key = $req->cookies->{session_key} || rand();
            my $cnt = ++$SESSION_STORE{$session_key};
            note "CNT: $cnt";
            my $res = Plack::Response->new(
                200, [], ["OK ${cnt}"]
            );
            $res->cookies->{'session_key'} = $session_key;
            return $res->finalize;
        };
    });
}

sub Plack::Request::uri_for {
    my($self, $path, $args) = @_;
    my $uri = $self->base;
    $uri->path($uri->path . $path);
    $uri->query_form(@$args) if $args;
    $uri;
}
