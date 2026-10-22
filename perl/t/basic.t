use strict;
use warnings;
use Test::More tests => 1;
use lib 'lib';
use Easyblobs::Test::Hello;

is( Easyblobs::Test::Hello->greet('easyblobs'), 'hello easyblobs', 'greets' );
