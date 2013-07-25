package Positron::Expression;
our $VERSION = 'v0.0.4'; # VERSION

=head1 NAME

Positron::Expression - a simple language for template parameters

=head1 VERSION

version v0.0.4

=head1 SYNOPSIS

    use Positron::Expression;

    my $env   = Positron::Environment->new({ key => 'value' });
    my $value = Positron::Expression::evaluate($string, $env);

=head1 DESCRIPTION

A simple expression language for templating constructs.
The main function, C<evaluate>, takes an expression as a string and a
L<Positron::Environment> object, and evaluates the two.
The result is a scalar value.

=head1 GRAMMAR

The grammar is basically built up of the following rules.
The exact grammar is available as a package variable
C<$Positron::Expression::grammar>; this is a string which is fed to
L<Parse::RecDescent> starting at the token C<expression>.

=head2 Whitespace

Whitespace is generally allowed between individual parts of the grammar.

=head2 Literals

    4 , -3.8 , "A string" , 'another string' , `a third string`

The grammar allows for literal strings and numbers. Numbers are integers or
floating point numbers. Notations with exponents or with different bases are
not supported. Negative numbers are possible.

Strings are delimited by double quotes, single quotes, or backticks.
Strings cannot contain their own delimiters; with three delimiters to choose
from, though, this should cover most use cases.

=head2 Variable lookups

   a , key0 , ListValues , flag_not_possible

A single, non-deliminated word is looked up in the environment; that value
is returned.
This may be C<undef> if the environment does not contain such a key.

Words follow the rules for identifiers in most C-like languages (and Perl),
in that they may start with a letter or an underscore, and contain only
letters or underscores.
Currently, only ASCII letters are supported; this will hopefully change in
the future.

=head2 Function calls

   a() , b(0) , find_file("./root", filename)

Functions are looked up in the environment, like variables.
They obey the same rules for identifiers, and are expected to return an
anonymous function (a sub reference).

This function is then called with the evaluated arguments.
In the last example above, C<filename> is looked up in the environment, and
the resulting value passed as the second argument to the function.

All function calls are made in scalar context.

=head2 Subselects

Subselects allow you to to select a part of something else, like getting the
value for a given key in a hash, or an indexed entry in a list, or call a
method on an object etc.
In C<Positron::Expression>, these are denoted with a dot, C<.>, hence the
alternative name "dotted expression".
Subselects can be chained.

The following subselects are possible:

=head3 Array index

    a.0 , b.4.-1 , c.$i

Arrays are indexed by appending an integer to the variable or expression holding
the array.
Like Perl, indices start with 0, and negative indices count from the back.
The form C<< $<expression> >> can be used to take any expression that evaluates
to an integer as an index.

=head3 Hash index

    pos.x , server.link.url , authors."Ben Deutsch" , names.$current

Hashes are indexed by appending a key, an identifier or string,
to the variable or expression holding the hash.
Most keys in practice will fit the form of an identifier as above
(letters, digits, underscores).
If not, a quoted string can be used.
The form C<< $<expression> >> can again be used to take any expression that
evaluates to a string as the key.

=head3 Object attributes

    obj.length , task.parent.priority , obj.$attr

Object attributes work just like hash indices above, except they are called
on an object and look up that attribute.

(In Perl, this is the same as a method call without parameters.)

=head3 Object method calls

    img.make_src(320, 240) , abs(int(-4.2))

Method calls work like a mixture between attributes and function calls.
The method name is restricted to an actual key, however, and not a free-form
string or a C<$>-expression.

Like functions, methods are called in scalar context.

=head2 Nested expressions

    hash.(var).length , ports.(resource.server)

Expressions can be nested with parentheses.
The C<var> expression above is equivalent to C<hash.$var.length>, since
C<var> as an expression is a variable lookup in the environment.

=head2 Boolean combinations

    a ? !b , if ? then : else , !!empty

The C<?>, C<:> and C<!> operands stand for "and", "or" and "not", respectively.
This terminology, while a bit obscure, is the mirror of Python's
C<a and b or c> ternary operator replacement.
In practice, this allows for some common use cases:

=head3 Not

The C<!> operator has a higher precedence than C<?> or C<:>, binding closer.
It reverses the "truth" of the expression it precedes.

B<Note>: unlike pure Perl, a reference to an empty array or an empty hash counts as false!
In Perl, it would be true because all references are true, barring overloading; only non-reference
empty arrays and hashes are false.
Positron's use is closer related to the Perl usages of C<if ( $@list )> than C<if ( $list )>,
and is typically what you mean.

=head3 Conditional values: And

    only_if ? value , first_cond ? second_cond ? result

The C<?> operator is a short-circuiting C<&&> or C<and> equivalent.
If the left hand side is false, it is returned, otherwise the right hand side is returned.
It is chainable, and left associative.

The most common use case is text insertion with a condition which is C<''> when false;
the right hand text is only inserted if the condition is true.

=head3 Defaults: Or

    first_try : second_try : third_try

The C<:> operator is a short-circuiting C<||> or C<or> equivalent.
If the left hand side is true, it is returned, otherwise the right hand side is returned.
It is chainable, left associative, and has the same precedence as C<?>.

The most common use case is to provide a chain of fallback values, selecting the first
fitting (i.e. true) one.

=head3 Ternary Operator

    if ? then : else

Taken together, the C<?> and C<:> operators form the well-known ternary operator: if the
left-most term is true, the middle term is chosen; else the right-most term is.

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

=head1 FUNCTIONS

=head2 evaluate

    my $value = Positron::Expression::evaluate($string, $environment);

Evaluates the expression in C<$string> with the L<Positron::Environment> C<$env>.
The result is always a scalar value, which may be a true scalar or a reference.
For example, the expression C<x> with the environment C<< { x => [1] } >>
will evaluate to a reference to an array with one element.

=cut

sub evaluate {
    my ($string, $environment) = @_;
    my $tree = parse($string);
    # Force scalar context, always
    return scalar(_evaluate($tree, $environment));
}

=head2 parse

    my $tree = Positron::Expression::parse($string);

Parses the string in the first argument, and returns an abstract parse tree.
The exact form of the tree is not important, it is usually a structure made
of nested array references. The important part is that it contains no
blessed references, only strings, numbers, arrays and hashes (that is, references
to those).

This makes it easy to serialize the tree, for distributed caching or
persistant storage, if parsing time is critical.

See also C<reduce> to continue the evaluation.

=cut

sub parse {
    my ($string) = @_;

    # lazy build, why not
    if (not $parser) {
        $parser = Parse::RecDescent->new($grammar);
    }
    return $parser->expression($string);
}

=head2 reduce

    my $value = Positron::Expression::reduce($tree, $environment);

The companion of C<parse>, this function takes an abstract parse tree and
returns a scalar value. Essentially,

    my $tree  = Positron::Expression::parse($string);
    my $value = Positron::Expression::reduce($tree, $environment);

is equivalent to

    my $value = Positron::Expression::evaluate($string, $environment);

=cut

sub reduce {
    my ($tree, $environment) = @_;
    return scalar(_evaluate($tree, $environment));
}

=head2 true

In Perl, empty lists and hashes count as false. The only way for C<Positron::Environment>
to contain lists and hashes is as array or hash references. However, these count as C<true>
in Perl, even if they reference an empty array or hash.

To aid decisions in templates, the function C<true> returns a false value for references to
empty arrays or hashes, and a true value for non-empty ones.
Other values, such as plain scalars, blessed references, subroutine references or C<undef>,
are returned verbatim.
Their truth values are therefore up to Perl (a reference blessed into a package with an
overloaded C<bool> method may still return false, for example.

=cut

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

1; # End of Positron::Expression

__END__

=head1 AUTHOR

Ben Deutsch, C<< <ben at bendeutsch.de> >>

=head1 BUGS

None known so far, though keep in mind that this is alpha software.

Please report any bugs or feature requests to C<bug-positron at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Positron>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

This module is part of the Positron distribution.

You can find documentation for this distribution with the perldoc command.

    perldoc Positron

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Positron>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Positron>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Positron>

=item * Search CPAN

L<http://search.cpan.org/dist/Positron/>

=back


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Ben Deutsch. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
See L<http://dev.perl.org/licenses/> for more information.

=cut
