package Positron::DataTemplate;
our $VERSION = 'v0.0.2'; # VERSION

=head1 NAME

Positron::DataTemplate - templating plain data to plain data

=head1 VERSION

version v0.0.2

=head1 SYNOPSIS

    my $engine   = Positron::DataTemplate->new();
    my $template = { contents => ['@list', '$title'] };
    my $data     = { list => [
        { title => 'first title', url => '/first-title.html' },
        { title => 'second title', url => '/second-title.html' },
    ] };
    my $result   = $engine->process($template, $data);
    # { contents => [ 'first title', 'second title' ] }

=head1 DESCRIPTION

C<Positron::DataTemplate> is a templating engine. Unlike most templating engines,
though, it does not work on text, but on raw data: the template is (typically)
a hash or array reference, and the result is one, too.

This module rose from a script that regularly produced HTML snippets on disk,
using regular, text-based templates. Each use case used the same data, but a different
template. For one use case, however, the output was needed in
JSON format, not HTML. One solution would have been to use the text-based
templating system to produce a valid JSON document (quite risky). The other solution,
which was taken at that time, was to transform the input data into the desired
output structure in code, and use a JSON serializer on that, bypassing the template
output.

The third solution would have been to provide a template that did not directly
produce the serialised JSON text, but described the data structure transformation
in an on-disc format. By working only with structured data, and never with text,
the serialized output must always be valid JSON.

This (minus the serialization) is the domain of C<Positron::DataTemplate>.

=head1 EXAMPLES

This code is still being worked on. This includes the documentation. In the meanwhile,
please use the following examples (and some trial & error) to gain a first look.
Alternatively, if you have access to the tests of this distribution, these also
give some examples.

=head2 Text replacement

  [ '$one', '{$two}', 'and {$three}' ] + { one => 1, two => 2, three => 3 }
  -> [ '1', '2', 'and 3' ]

=head2 Direct inclusion

  [ '&this', '&that' ] + { this => [1, 2], that => { 3 => 4 } }
  -> [ [1, 2], { 3 => 4} ]

=head2 Loops

  { titles => ['@list', '{$id}: {$title}'] }
  + { list => [ { id => 1, title => 'one' }, { id => 2, title => 'two' } ] }
  -> { titles => [ '1: one', '2: two' ] }

=head2 Conditions

  { checked => ['?active', 'yes', 'no] } + { active => 1 }
  -> { checked => 'yes' }

=cut

use v5.10;
use strict;
use warnings;

use Carp qw( croak );
use Data::Dump qw(dump);
use Positron::Environment;
use Positron::Expression;

sub new {
    # Note: no Moose; we have no inheritance or attributes to speak of.
    my ($class) = @_;
    my $self = {
        include_paths => ['.'],
    };
    return bless($self, $class);
}

sub process {
    my ($self, $template, $env) = @_;
    # Returns (undef) in list context - is this correct?
    return undef unless defined $template;
    $env = Positron::Environment->new($env);
    my @return = $self->_process($template, $env);
    # If called in scalar context, the caller "knows" that there will
    # only be one element -> shortcut it.
    return wantarray ? @return : $return[0];
}

sub _process {
    my ($self, $template, $env) = @_;
    if (not ref($template)) {
        return $self->_process_text($template, $env);
    } elsif (ref($template) eq 'ARRAY') {
        return $self->_process_array($template, $env);
    } elsif (ref($template) eq 'HASH') {
        return $self->_process_hash($template, $env);
    }
    return $template; # TODO: deep copy?
}

sub _process_text {
    my ($self, $template, $env) = @_;
    if ($template =~ m{ \A [&,] (.*) \z}xms) {
        return Positron::Expression::evaluate($1, $env);
    } elsif ($template =~ m{ \A \$ (.*) \z}xms) {
        return "" . Positron::Expression::evaluate($1, $env);
    } elsif ($template =~ m{ \A \x23 (\+?) }xms) {
        return (wantarray and not $1) ? () : '';
    } elsif ($template =~ m{ \A \. \s* "([^"]+)" }xms) {
        my $filename = $1;
        require JSON;
        require File::Slurp;
        my $json = JSON->new();
        my $file = undef;
        foreach my $path (@{$self->{include_paths}}) {
            if (-f $path . $filename) {
                $file = $path . $filename; # TODO: platform-independent chaining
            }
        }
        if ($file) {
            my $result = $json->decode(File::Slurp::read_file($file));
            return $self->_process($result, $env);
        } else {
            croak "Can't find template '$filename' in " . join(':', @{$self->{include_paths}});
        }
    } elsif ($template =~ m{ \A \^ \s* (.*) }xms) {
        my $function = Positron::Expression::evaluate($1, $env);
        return $function->();
    } else {
        $template =~ s{
            \{ \$ ([^\}]*) \}
        }{
            my $replacement = Positron::Expression::evaluate($1, $env) // '';
            "$replacement";
        }xmseg;
        $template =~ s{
           (\s*) \{ \x23 (-?) ([^\}]*) \} (\s*)
        }{
            $2 ? '' : $1 . $4;
        }xmseg;
        return $template;
    }
}

sub _process_array {
    my ($self, $template, $env) = @_;
    return [] unless @$template;
    my @elements = @$template;
    if ($elements[0] =~ m{ \A \@ (.*) \z}xms) {
        # list iteration
        my $clause = $1;
        shift @elements;
        my $result = [];
        my $list = Positron::Expression::evaluate($clause, $env); # must be arrayref!
        foreach my $el (@$list) {
            my $new_env = Positron::Environment->new( $el, { parent => $env } );
            push @$result, map $self->_process($_, $new_env), @elements;
        }
        return $result;
    } elsif ($elements[0] =~ m{ \A \? (.*) \z}xms) {
        # conditional
        my $clause = $1;
        shift @elements;
        my $has_else = (@elements > 1) ? 1 : 0;
        my $cond = Positron::Expression::evaluate($clause, $env); # can be anything!
        # for Positron, empty lists and hashes are false!
        # TODO: $cond = Positron::Expression::true($cond);
        if (ref($cond) eq 'ARRAY' and not @$cond) { $cond = 0; }
        if (ref($cond) eq 'HASH'  and not %$cond) { $cond = 0; }
        if (not $cond and not $has_else) {
            # no else clause, return empty list on false
            return ();
        }
        my $then = shift @elements;
        my $else = shift @elements;
        my $result = $cond ? $then : $else;
        return $self->_process($result, $env);
    } else {
        my $return = [];
        # potential structural comments
        my $skip_next = 0;
        my $capturing_function = 0;
        foreach my $element (@elements) {
            if ($element =~ m{ \A // }xms) {
                last; # nothing more
            } elsif ($element =~ m{ \A / }xms) {
                $skip_next = 1;
            } elsif ($element =~ m{ \A \^ \s* (.*) }xms) {
                $capturing_function = Positron::Expression::evaluate($1, $env);
                # do not push!
            } elsif ($skip_next) {
                $skip_next = 0;
            } elsif ($capturing_function) {
                # we have a capturing function waiting for input
                my $arg = $self->_process($element, $env);
                push @$return, $capturing_function->($arg);
                # no more waiting function
                $capturing_function = 0;
            } else {
                push @$return, $self->_process($element, $env);
            }
        }
        if ($capturing_function) {
            # Oh no, a function waiting for args?
            push @$return, $capturing_function->();
        }
        return $return;
    }
}
sub _process_hash {
    my ($self, $template, $env) = @_;
    return {} unless %$template;
    my %result = ();
    my $hash_construct = undef;
    my $switch_construct = undef;
    foreach my $key (keys %$template) {
        if ($key =~ m{ \A \% (.*) \z }xms) {
            $hash_construct = [$key, $1]; last;
        } elsif ($key =~ m{ \A \? (.*) \z }xms) {
            $switch_construct = [$key, $1]; last;
        }
    }
    if ($hash_construct) {
        my $e_content = Positron::Expression::evaluate($hash_construct->[1], $env);
        croak "Error: result of expression '".$hash_construct->[1]."' must be hash" unless ref($e_content) eq 'HASH';
        while (my ($key, $value) = each %$e_content) {
            my $new_env = Positron::Environment->new( { key => $key, value => $value }, { parent => $env } );
            my $t_content = $self->_process( $template->{$hash_construct->[0]}, $new_env);
            croak "Error: content of % construct must be hash" unless ref($t_content) eq 'HASH';
            # copy into result
            foreach my $k (keys %$t_content) {
                $result{$k} = $t_content->{$k};
            }
        }
    } elsif ($switch_construct) {
        my $e_content = Positron::Expression::evaluate($switch_construct->[1], $env); # The switch key
        if (defined $e_content and exists $template->{$switch_construct->[0]}->{$e_content}) {
            return $self->_process($template->{$switch_construct->[0]}->{$e_content}, $env);
        } elsif (exists $template->{$switch_construct->[0]}->{'?'}) {
            return $self->_process($template->{$switch_construct->[0]}->{'?'}, $env);
        } else {
            return ();
        }
    } else {
        # simple copy
        while (my ($key, $value) = each %$template) {
            if ($key =~ m{ \A / }xms) {
                # structural comment
                next;
            }
            if ($value =~ m{ \A / }xms) {
                # structural comment (forbidden on values)
                croak "Cannot comment out a value";
            }
            if ($key =~ m{ \A \^ \s* (.*)}xms) {
                # consuming function call (interpolates)
                my $func = Positron::Expression::evaluate($1, $env);
                my $value_in = $self->_process($value, $env);
                my $hash_out = $func->($value_in);
                # interpolate
                foreach my $k (keys %$hash_out) {
                    $result{$k} = $hash_out->{$k};
                }
                next;
            }
            $key = $self->_process($key, $env);
            $value = $self->_process($value, $env);
            $result{$key} = $value;
        }
    }
    return \%result;
}

sub add_include_paths {
    my ($self, @paths) = @_;
    push @{$self->{'include_paths'}}, @paths;
}

1;
