#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    use_ok('Positron::DataTemplate');
}

my $template = Positron::DataTemplate->new();
$template->add_include_paths('t/Positron/DataTemplate/');

my $data = {
    'list' => [{ id => 1, title => 'eins'}, { id => 2, title => 'zwei' }],
    'hash' => { 1 => 2 },
};

is_deeply($template->process( [1, '. "plain.json"', 2], $data ), [1, { one => 1 }, 2], "Include a plain file");
is_deeply($template->process( [1, '. "structure.json"', 2], $data ), [1, { one => { 1 => 2 }, two => ['eins', 'zwei'] }, 2], "Include a file with structure");

done_testing();
