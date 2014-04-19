#!/usr/bin/perl

use strict;
use warnings;
use 5.10.0;

use Data::Dumper;
$Data::Dumper::Deparse = 1;

my $perl = eval 'sub { "world" }';
print Dumper  $perl;

# no strict 'refs';
say &$perl();
