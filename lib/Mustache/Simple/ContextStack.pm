package Mustache::Simple::ContextStack;

use strict;
use warnings;
use 5.10.0;

use Carp;

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
    croak "Context must be a hash: $context" unless ref $context eq 'HASH';
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
	return $context->{$element} if exists $context->{$element};
    }
    return undef;
}

1;
