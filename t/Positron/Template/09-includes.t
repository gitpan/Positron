#!/usr/bin/perl

use strict;
use warnings;

use Storable;
use Test::More;
use Test::Exception;

BEGIN {
    use_ok('Positron::Template');
}

my $template = Positron::Template->new();
$template->add_include_paths('t/Positron/Template/');

my $dom = 
[ 'div', {},
    [ 'div', { style => "{. `include-outer-1.store`}" }, ],
];
my $inner =
[ 'p', {},
    "It works!",
];

sub dom {
    my ($quant, $filetype) = @_;
    return 
    [ 'section', {},
        [ 'div', { style => "{.$quant `include-$filetype.store`}" },
            "Placeholder content",
        ],
    ];
}

# Normally, the current versions of these should be included with the
# distribution. This is an author's helper, should the test ever need to
# be amended.
sub ensure_filetype {
    my ($filetype) = @_;
    my $filename = 't/Positron/Template/' . "include-$filetype.store";
    if (not -e $filename) {
        # -e, not -r - if it's not readable, don't try writing, die later
        my $dom = {
            plain => [ 'p', {}, "It works!", ],
            structure => 
            ['p', {},
                'It {$works}!',
                [ 'ul', { style => '{@list}'},
                    [ 'li', {}, '{$title}' ],
                ]
            ],
        }->{$filetype} or die "Unknown filetype $filetype!";
        store($dom, $filename) or die "Storable::store failure";
    }
}

my $data = {
    'list' => [{ id => 1, title => 'eins'}, { id => 2, title => 'zwei' }],
    'hash' => { 1 => 2 },
    'works' => 'does',
};

ensure_filetype('plain');

is_deeply($template->process( dom('', 'plain'), $data ), ['section', {}, ['p', {}, "It works!"]], "Include a plain file, no quantifier");
is_deeply($template->process( dom('+', 'plain'), $data ), ['section', {}, ['div', {}, ['p', {}, "It works!"]]], "Include a plain file");

ensure_filetype('structure');

my $expected_inner = ['p', {},
    'It does!',
    ['ul', {},
        ['li', {}, 'eins'],
        ['li', {}, 'zwei'],
    ],
];

is_deeply($template->process( dom('', 'structure'), $data ), ['section', {}, $expected_inner], "Include a plain file, no quantifier");
is_deeply($template->process( dom('+', 'structure'), $data ), ['section', {}, ['div', {}, $expected_inner]], "Include a plain file");

throws_ok {
    $template->process( dom('', 'nonexisting'), $data );
} qr{Could not find}, "Exception on non-existing file";

dies_ok {
    $template->process( dom('', 'malformed'), $data );
} "Exception on malformed file";

done_testing();
