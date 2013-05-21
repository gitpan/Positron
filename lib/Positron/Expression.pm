package Positron::Expression;
our $VERSION = 'v0.0.2'; # VERSION

=head1 NAME

Positron::Expression - a simple language for template parameters

=head1 VERSION

version v0.0.2

=cut

use v5.10;
use strict;
use warnings;

use Carp qw(croak);
use Data::Dump qw(dump);
use Positron::Environment;
use Parse::RecDescent;
use Scalar::Util qw(blessed);

# The following grammer creates a "parse tree" 

our $grammar = <<'EOT';
# We start with our "boolean / ternary" expressions
expression: <leftop: alternative /([:?])/ alternative> { @{$item[1]} == 1 ? $item[1]->[0] : ['expression', @{$item[1]}]; }
alternative: '!' alternative { ['not', $item[2]]; } | operand

# strings and numbers cannot start a dotted expression
# in fact, numbers can have decimal points.
operand: string | number | lterm ('.' rterm)(s) { ['dot', $item[1], @{$item[2]}] } | lterm

# The first part of a dotted expression is looked up in the environment.
# The following parts are parts of whatever came before, and consequently looked
# up there.
lterm: '(' expression ')' { $item[2] } | funccall | identifier | '$' lterm { ['env', $item[2]] }
rterm: '(' expression ')' { $item[2] } | methcall | key | string | integer | '$' lterm { $item[2] }

# Strings currently cannot contain their delimiters, sorry.
string: '"' /[^"]*/ '"' { $item[2] } | /\'/ /[^\']*/ /\'/ { $item[2] } | '`' /[^`]*/ '`' { $item[2] }

identifier: /[a-zA-Z_]\w*/ {['env', $item[1]]}
key: /[a-zA-Z_]\w*/ { $item[1] }
number: /[+-]?\d+(?:\.\d+)?/ { $item[1] }
integer: /[+-]?\d+/ { $item[1] }

# We need "function calls" and "method calls", since with the latter, the function
# is *not* looked up in the environment.
funccall: identifier '(' expression(s? /\s*,\s*/) ')' { ['funccall', $item[1], @{$item[3]}] }
methcall: key '(' expression(s? /\s*,\s*/) ')' { ['methcall', $item[1], @{$item[3]}] }
EOT

our $parser = undef;

sub parse {
    my ($string) = @_;

    # lazy build, why not
    if (not $parser) {
        $parser = Parse::RecDescent->new($grammar);
    }
    return $parser->expression($string);
}

sub evaluate {
    my ($string, $environment) = @_;
    my $tree = parse($string);
    return _evaluate($tree, $environment);
}

# We count [] and {} as false!
sub true {
    my ($it) = @_;
    if (ref($it)) {
        if (ref($it) eq 'ARRAY') {
            return @$it;
        } elsif (ref($it) eq 'HASH') {
            return scalar(keys %$it);
        } else {
            return $it;
        }
    } else {
        return $it;
    }
}

sub _evaluate {
    my ($tree, $env, $obj) = @_;
    if (not ref($tree)) {
        return $tree;
    } else {
        my ($operand, @args) = @$tree;
        if ($operand eq 'env') {
            my $key = _evaluate($args[0], $env);
            return $env->get($key);
        } elsif ($operand eq 'funccall') {
            my $func = shift @args; # probably [env]
            $func = _evaluate($func, $env);
            @args = map _evaluate($_, $env), @args;
            return $func->(@args);
        } elsif ($operand eq 'methcall') {
            # Needs $obj argument
            my $func = shift @args; # probably literal
            $func = _evaluate($func, $env);
            @args = map _evaluate($_, $env), @args;
            return ($obj->can($func))->($obj, @args);
        } elsif ($operand eq 'not') {
            my $what = _evaluate($args[0], $env);
            return ! true($what);
        } elsif ($operand eq 'expression') {
            my $left = _evaluate(shift @args, $env);
            while (@args) {
                my $op    = shift @args;
                my $right = shift @args;
                if ($op eq '?') {
                    # and
                    if (true($left)) {
                        $left = _evaluate($right, $env);
                    }
                } else {
                    # or
                    if (!true($left)) {
                        $left = _evaluate($right, $env);
                    }
                }
            }
            return $left;
        } elsif ($operand eq 'dot') {
            my $left = _evaluate(shift @args, $env);
            while (@args) {
                if (blessed($left)) {
                    my $key = shift @args;
                    if (ref($key) and ref($key) eq 'ARRAY' and $key->[0] eq 'methcall' ) {
                        # Method, like 'funccall' but pass the object as extra parameter
                        $left = _evaluate($key, $env, $left);
                    } else {
                        # Attribute or similar.
                        # In Perl, still a method (without additional arguments)
                        $key = _evaluate($key, $env);
                        $left = ($left->can($key))->($left);
                    }
                } elsif (ref($left) eq 'HASH') {
                    my $key = _evaluate(shift @args, $env);
                    $left = $left->{$key};
                } elsif (ref($left) eq 'ARRAY') {
                    my $key = _evaluate(shift @args, $env);
                    $left = $left->[ $key ];
                } else {
                    die "Asked to subselect a scalar";
                }
            }
            return $left;
        }
    }
}

1;
