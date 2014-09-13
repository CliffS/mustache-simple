package Mustache::Simple::ContextStack;

use strict;
use warnings;
use 5.10.1;

our $VERSION = v1.3.0;

use Scalar::Util qw(blessed reftype);
use Carp;
our @CARP_NOT = qw(Mustache::Simple);

#use Data::Dumper;
#$Data::Dumper::Useqq = 1;
#$Data::Dumper::Deparse = 1;

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
        if (blessed $context)
        {
            my $meth;
            return sub { $context->$meth } if $meth = $context->can($element);
        }
	next unless reftype $context eq 'HASH';
	return $context->{$element} if exists $context->{$element};
    }
    return undef;
}

sub top
{
    my $self = shift;
    return $self->[-1];
}

1;
