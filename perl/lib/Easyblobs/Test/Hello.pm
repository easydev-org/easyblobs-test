package Easyblobs::Test::Hello;

use strict;
use warnings;

our $VERSION = '1.0.0';

sub greet {
    my ($class, $name) = @_;
    return "hello $name";
}

1;
