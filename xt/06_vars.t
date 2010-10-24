use strict;
use Test::Requires qw(Test::Vars);
all_vars_ok ignore_vars => [
    '$host', '$port', # in remove_conn_cache
];
