use Test::More;
eval 'use Test::Valgrind';
plan skip_all =>
  'Test::Valgrind is required to test your distribution with valgrind'
  if $@;
leaky();
