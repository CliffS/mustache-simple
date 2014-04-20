#!/usr/bin/perl

use strict;
use warnings;
use 5.10.0;

use lib '/home/cliff/src/git/mustache-simple/lib';
use Mustache::Simple;
use YAML::XS qw(LoadFile);
use Data::Dumper;
use Attribute::Boolean;

my $yaml = LoadFile('/home/cliff/src/git/mustache-simple/t/specs/sections.yml');
#my $yaml = LoadFile('/home/cliff/src/git/mustache-simple/t/specs/inverted.yml');
#my $yaml = LoadFile('/home/cliff/src/git/mustache-simple/t/specs/interpolation.yml');

foreach my $test (@{$yaml->{tests}})
{
    next if $test->{name} =~ /Decimal Interpolation/;
    next if $test->{name} =~ /Implicit Iterator/;
    say $test->{name};
    my $mus = new Mustache::Simple;
    my $result = $mus->render($test->{template}, $test->{data});
    next if $result eq $test->{expected};
    say "Expected:\n$test->{expected}";
    say "Got:\n$result";
    #print Dumper $test->{data};
    #last;
}

