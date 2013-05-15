#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    use_ok('Positron::DataTemplate');
}

my $template = Positron::DataTemplate->new();

my $data = {
    double => sub {
        my ($arg) = @_;
        if (@_) {
            return $arg * 2;
        } else {
            return 'NaN';
        }
    },
    gethash => sub {
        if (@_) {
            return { arg => shift @_ };
        } else {
            return { key => 'value' };
        }
    },
};

# Do we even allow this? Just means "with no arguments"...
is_deeply($template->process('^double', $data), 'NaN', "Without anything (bare)");

is_deeply($template->process(['^double'], $data), ['NaN'], "Without anything (in list)");
is_deeply($template->process(['^double', 3], $data), [6], "With argument");
is_deeply($template->process([5, '^double', 3, 7], $data), [5, 6, 7], "With surroundings");

is_deeply($template->process( { 'one' => '^gethash' }, $data), { 'one' => { key => 'value' } }, "In hash as value"); 
is_deeply($template->process( { 'one' => 'eins', '^gethash' => 'passed' }, $data), { 'one' => 'eins', arg => 'passed' }, "In hash as key"); 

done_testing();
