#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    use_ok('Positron::Environment');
}

my $env = Positron::Environment->new({ 
    'key1' => 'value1', 
    'key2' => ['value2a','value2b'], 
    'key3' => {'a' => 1, 'b' => 2 },
    'key4' => {'a' => {'x' => 'one', 'y' => 'two',}, 'b' => [99, 98]},
}, { immutable => 1 },);

is($env->resolve('key1'), 'value1', "Simple scalar");

# Subselects can, and will, get complicated. Function calls, methods,
# Parameters, literal strings with entities.
# On top of that, we have ternary operators and filters.
# We start simple.
is_deeply($env->resolve('key2'), ['value2a', 'value2b'], "Ref scalar");
is_deeply($env->resolve('key2.0'), 'value2a', "Subselect of array[0]");
is_deeply($env->resolve('key2.1'), 'value2b', "Subselect of array[1]");
is_deeply($env->resolve('key3.a'), 1, 'Subselect of hash');

is_deeply($env->resolve('key4.a.x'), 'one', 'Hash of hash');
is_deeply($env->resolve('key4.b.1'), '98', 'Hash of array');


done_testing();

