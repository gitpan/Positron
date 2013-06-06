package Positron::DataTemplate;
our $VERSION = 'v0.0.3'; # VERSION

=head1 NAME

Positron::DataTemplate - templating plain data to plain data

=head1 VERSION

version v0.0.3

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

=head2 Interpolation (works with a lot of constructs)

  [1, '&list', 4] + { list => [2, 3] }
  -> [1, [2, 3], 4]
  [1, '&-list', 4] + { list => [2, 3] }
  -> [1, 2, 3, 4]
  [1, '<', '&list', 4] + { list => [2, 3] }
  -> [1, 2, 3, 4]

  { '< 1' => { a => 'b' }, '< 2' => { c => 'd', e => 'f' }
  -> { a => 'b', c => 'd', e => 'f' }
  { '< 1' => '&hash', two => 2 } + { hash => { one => 1 } }
  -> { one => 1, two => 2 }

=head2 Comments

  'this is {#not} a comment' -> 'this is a comment'
  [1, '#comment', 2, 3]      -> [1, 2, 3]
  [1, '/comment', 2, 3]      -> [1, 3]
  [1, '//comment', 2, 3]     -> [1]
  { 1 => 2, '#3' => 4 }      -> { 1 => 2, '' => 4 }
  { 1 => 2, '/3' => 4 }      -> { 1 => 2 }

=head2 File inclusion (requires L<JSON> and L<File::Slurp>)

  [1, '. "/tmp/data.json"', 3] + '{ key: "value"}'
  -> [1, { key => 'value' }, 3]

=head2 Funtions on data

  [1, '^len', "abcde", 2] + { len => \&CORE::length }
  -> [1, 5, 2]

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
    my @return = $self->_process($template, $env, '', 0);
    # If called in scalar context, the caller "knows" that there will
    # only be one element -> shortcut it.
    return wantarray ? @return : $return[0];
}

sub _interpolate {
    my ($value, $context, $interpolate) = @_;
    return $value unless $interpolate;
    if ($context eq 'array' and ref($value) eq 'ARRAY') {
        return @$value;
    } elsif ($context eq 'hash' and ref($value) eq 'HASH') {
        return %$value;
    } else {
        return $value;
    }
}

sub _process {
    my ($self, $template, $env, $context, $interpolate) = @_;
    if (not ref($template)) {
        return $self->_process_text($template, $env, $context, $interpolate);
    } elsif (ref($template) eq 'ARRAY') {
        return $self->_process_array($template, $env, $context, $interpolate);
    } elsif (ref($template) eq 'HASH') {
        return $self->_process_hash($template, $env, $context, $interpolate);
    }
    return $template; # TODO: deep copy?
}

sub _process_text {
    my ($self, $template, $env, $context, $interpolate) = @_;
    if ($template =~ m{ \A [&,] (-?) (.*) \z}xms) {
        if ($1) { $interpolate = 1; }
        return _interpolate(Positron::Expression::evaluate($2, $env), $context, $interpolate);
    } elsif ($template =~ m{ \A \$ (.*) \z}xms) {
        return "" . Positron::Expression::evaluate($1, $env);
    } elsif ($template =~ m{ \A \x23 (\+?) }xms) {
        return (wantarray and not $1) ? () : '';
    } elsif ($template =~ m{ \A \. (-?) \s* (.*) }xms) {
        if ($1) { $interpolate = 1; }
        my $filename = Positron::Expression::evaluate($2, $env);
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
            return $self->_process($result, $env, $context, $interpolate);
        } else {
            croak "Can't find template '$filename' in " . join(':', @{$self->{include_paths}});
        }
    } elsif ($template =~ m{ \A \^ (-?) \s* (.*) }xms) {
        if ($1) { $interpolate = 1; }
        my $function = Positron::Expression::evaluate($2, $env);
        return _interpolate($function->(), $context, $interpolate);
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
    my ($self, $template, $env, $context, $interpolate) = @_;
    return _interpolate([], $context, $interpolate) unless @$template;
    my @elements = @$template;
    if ($elements[0] =~ m{ \A \@ (-?) (.*) \z}xms) {
        # list iteration
        if ($1) { $interpolate = 1; }
        my $clause = $2;
        shift @elements;
        my $result = [];
        my $list = Positron::Expression::evaluate($clause, $env); # must be arrayref!
        foreach my $el (@$list) {
            my $new_env = Positron::Environment->new( $el, { parent => $env } );
            # Do not interpolate here, interpolate the result
            push @$result, map $self->_process($_, $new_env, 'array', 0), @elements;
        }
        return _interpolate($result, $context, $interpolate);
    } elsif ($elements[0] =~ m{ \A \? (-?) (.*) \z}xms) {
        # conditional
        if ($1) { $interpolate = 1; }
        my $clause = $2;
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
        return $self->_process($result, $env, $context, $interpolate);
    } else {
        my $return = [];
        # potential structural comments
        my $skip_next = 0;
        my $capturing_function = 0;
        my $interpolate_next = 0;
        my $is_first_element = 1;
        foreach my $element (@elements) {
            if ($element =~ m{ \A // (-?) }xms) {
                if ($is_first_element and $1) { $interpolate = 1; }
                last; # nothing more
            } elsif ($element =~ m{ \A / (-?) }xms) {
                if ($is_first_element and $1) { $interpolate = 1; }
                $skip_next = 1;
            } elsif ($element =~ m{ \A \^ (-?) \s* (.*) }xms) {
                if ($is_first_element and $1) { $interpolate = 1; }
                $capturing_function = Positron::Expression::evaluate($2, $env);
                # do not push!
            } elsif ($skip_next) {
                $skip_next = 0;
            } elsif ($capturing_function) {
                # we have a capturing function waiting for input
                my $arg = $self->_process($element, $env);
                push @$return, $capturing_function->($arg);
                # no more waiting function
                $capturing_function = 0;
            } elsif ($element =~ m{ \A < }xms) {
                $interpolate_next = 1;
            } else {
                push @$return, $self->_process($element, $env, 'array', $interpolate_next);
                $interpolate_next = 0;
            }
            $is_first_element = 0; # not anymore
        }
        if ($capturing_function) {
            # Oh no, a function waiting for args?
            push @$return, $capturing_function->();
        }
        return _interpolate($return, $context, $interpolate);
    }
}
sub _process_hash {
    my ($self, $template, $env, $context, $interpolate) = @_;
    return _interpolate({}, $context, $interpolate) unless %$template;
    my %result = ();
    my $hash_construct = undef;
    my $switch_construct = undef;
    foreach my $key (keys %$template) {
        if ($key =~ m{ \A \% (.*) \z }xms) {
            $hash_construct = [$key, $1]; last;
        } elsif ($key =~ m{ \A \? (.*) \z }xms) {
            # '?-': activate interpolate ?
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
        # '<': pass downwards ?
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
        # '<': find first, and interpolate
        # do by sorting keys alphabetically
        my @keys = sort {
            if($a =~ m{ \A < }xms) {
                if ($b =~ m{ \A < }xms) {
                    return $a cmp $b;
                } else {
                    return -1;
                }
            } else {
                if ($b =~ m{ \A < }xms) {
                    return 1;
                } else {
                    return $a cmp $b;
                }
            }
        } keys %$template;
        foreach my $key (@keys) {
            my $value = $template->{$key};
            if ($key =~ m{ \A < }xms) {
                # interpolate
                my %values = $self->_process($value, $env, 'hash', 1);
                %result = (%result, %values);
                next;
            }
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
                my $value_in = $self->_process($value, $env, '', 0);
                my $hash_out = $func->($value_in);
                # interpolate
                foreach my $k (keys %$hash_out) {
                    $result{$k} = $hash_out->{$k};
                }
                next;
            }
            $key = $self->_process($key, $env, '', 0);
            $value = $self->_process($value, $env, '', 0);
            $result{$key} = $value;
        }
    }
    return _interpolate(\%result, $context, $interpolate);
}

sub add_include_paths {
    my ($self, @paths) = @_;
    push @{$self->{'include_paths'}}, @paths;
}

1; # End of Positron::DataTemplate

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
