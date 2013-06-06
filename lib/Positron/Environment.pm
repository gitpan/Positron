package Positron::Environment;
our $VERSION = 'v0.0.3'; # VERSION

=head1 NAME

Positron::Environment - container class for template parameters

=head1 VERSION

version v0.0.3

=head1 SYNOPSIS

    use Positron::Environment;
    my $env   = Positron::Environment->new({ key1 => 'value 1', key2 => 'value 2'});
    my $child = Positron::Environment->new({ key1 => 'value 3'}, { parent => $env });

    say $env->get('key1');   # value 1
    say $env->get('key2');   # value 2
    say $child->get('key1'); # value 3
    say $child->get('key2'); # value 2

    $child->set( key2 => 'value 4' );
    say $child->get('key2'); # value 4
    say $env->get('key2');   # value 2

=head1 DESCRIPTION

C<Positron::Environment> is basically a thin wrapper around hashes (key-value mappings)
with hierarchy extensions. It is used internally by the C<Positron> template systems
to store template variables.

C<Positron::Environment> provides getters and setters for values. It can also optionally
refer to a parent environment. If the environment does not contain anything for an
asked-for key, it will ask its parent in turn.
Note that if a key refers to C<undef> as its value, this counts as "containing something",
and the parent will not be asked.

=cut

use v5.10;
use strict;
use warnings;
use Carp qw(croak);

=head1 CONSTRUCTOR

=head2 new

    my $env = Positron::Environment->new( \%data, \%options );

Creates a new environment which serves the data passed in a hash reference. The following options are supported:

=over 4

=item immutable

If set to a true value, the constructed environment will be immutable; calling the
C<set> method will raise an exception.

=item parent

A reference to another environment. If the newly constructed environment does not
contain a key when asked with C<get>, it will ask this parent environment (which
can have a parent in turn).

=back

=cut

sub new {
    my($class, $data, $options) = @_;
    $options //= {};
    my $self = {
        data => $data // {},
        immutable => $options->{'immutable'} // 0,
        # We don't need to weaken, since we are always pointing upwards only!
        parent => $options->{'parent'} // undef,
    };
    return bless($self, $class);
}

=head1 METHODS

=head2 get

    my $value = $env->get('key');

Returns the value stored under the key C<key> in the data of this environment.
This is very much like a standard hash ref. If this environment does not know
about this key (i.e. it does not exist in the data hash), it returns C<undef>,
unless a parent environment is set. In this case, it will recursively query
its parent for the key.

=cut

sub get {
    my ($self, $key) = @_;
    if (exists $self->{'data'}->{$key}) {
        return $self->{'data'}->{$key};
    } elsif ($self->{'parent'}) {
        return $self->{'parent'}->get($key);
    }
    return;
}

=head2 set

    my $value = $env->set('key', 'value');

Sets the key to the given value in this environment's data hash.
This call will croak if the environment has been marked as immutable.
Setting the value to C<undef> will effectively mask any parent; a C<get>
call will return C<undef> even if the parent has a defined value.

Returns the value again I<(this may change in future versions)>.

=cut

# Why do we need this, again?
# TODO: Should this delete if no value is passed?
sub set {
    my ($self, $key, $value) = @_;
    croak "Immutable environment being changed" if $self->{'immutable'};
    $self->{'data'}->{$key} = $value;
    return $value;
}

1; # End of Positron::Environment

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
