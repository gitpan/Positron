package Positron::Environment;
our $VERSION = 'v0.0.1'; # VERSION

=head1 NAME 

Positron::Environment - container class for template parameters

=head1 VERSION

version v0.0.1

=cut

use strict;
use warnings;
use Carp qw(croak);

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

# Gets recursively
sub get {
    my ($self, $key) = @_;
    if (exists $self->{'data'}->{$key}) {
        return $self->{'data'}->{$key};
    } elsif ($self->{'parent'}) {
        return $self->{'parent'}->get($key);
    }
    return;
}

# Sets, if mutable (non-recursive)
# Why do we need this, again?
# TODO: Should this delete if no value is passed?
sub set {
    my ($self, $key, $value) = @_;
    croak "Immutable environment being changed" if $self->{'immutable'};
    $self->{'data'}->{$key} = $value;
    return $value;
}

# "Subselects". For now, stick to scalars, arrays, hashes
sub resolve {
    my ($self, $key) = @_;
    if ($key =~ m{ (.*) \. ([^.]+) }xms) {
        my ($subselect, $index) = ($1, $2);
        my $lvalue = $self->resolve($subselect);
        if (ref($lvalue) eq 'HASH') {
            return $lvalue->{$index};
        } elsif (ref($lvalue) eq 'ARRAY' and $index =~ m{ \A \d+ \z }xms) {
            return $lvalue->[$index];
        } else {
            return undef; # always scalar
        }
    } else {
        return scalar($self->get($key));
    }
}

1;
