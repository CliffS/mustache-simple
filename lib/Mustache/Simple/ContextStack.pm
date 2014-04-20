package Mustache::Simple::ContextStack;

use strict;
use warnings;
use 5.10.0;

our $VERSION = v1.1.0;

use Carp;
our @CARP_NOT = qw(Mustache::Simple);

sub new
{
    my $class = shift;
    my $self = [];
    bless $self, $class;
}

sub push
{
    my $self = shift;
    my $context = shift;
    push @$self, $context;
}

sub pop
{
    my $self = shift;
    my $context = pop @$self;
    return $context;
}

sub search
{
    my $self = shift;
    my $element = shift;
    for (my $i = $#$self; $i >= 0; $i--)
    {
	my $context = $self->[$i];
	next unless ref $context eq 'HASH';
	return $context->{$element} if exists $context->{$element};
    }
    return undef;
}

sub top
{
    my $self = shift;
    return $self->[$#$self];
}

1;
