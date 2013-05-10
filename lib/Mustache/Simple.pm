package Mustache::Simple;

use strict;
use warnings;
use 5.10.0;
use utf8;

use version 0.77; our $VERSION = qv(v0.9.5);

use File::Spec;

use Carp;
use Data::Dumper;
$Data::Dumper::Useqq = 1;
$Data::Dumper::Deparse = 1;

=encoding utf8

=head1 NAME

Mustache::Simple - A simple Mustach Renderer

See L<http://mustache.github.com/>.

=head1 VERSION

This document describes Mustache::Simple version 0.9.0

=head1 SYNOPSIS

A typical Mustache template:

    my $template = <<EOT;
Hello {{name}}
You have just won ${{value}}!
{{#in_ca}}
Well, ${{taxed_value}}, after taxes.
{{/in_ca}}
EOT

Given the following hashref:

    my $context = {
	name => "Chris",
	value => 10000,
	taxed_value => 10000 - (10000 * 0.4),
	in_ca => 1
    };

Will produce the following:

    Hello Chris
    You have just won $10000!
    Well, $6000, after taxes.

using the following code:

    my $tache = new Mustache::Simple(
	throw => 1
    );
    my $output = $tache->render($template, $context);

=cut

=head1 DESCRIPTION

Mustache can be used for HTML, config files, source code - anything. It works
by expanding tags in a template using values provided in a hash or object.

There are no if statements, else clauses, or
for loops. Instead there are only tags. Some tags are replaced with a value,
some nothing, and others a series of values.

This is a simple perl implementation of the Mustache rendering.  It has
a single class method, new() to obtain an object and a single instance
method render() to convert the template and the hashref into the final
output.

=head2 Rationale

I wanted a simple rendering tool for Mustache that did not require any
subclassing.  It has currently been tested only against the list of examples on
the mustache manual page: L<http://mustache.github.com/mustache.5.html> and
the mustache demo page: L<http://mustache.github.com/#demo>.

=cut


#############################################################
##
##  Helper Functions
##
##

# Generate a regular expression for iteration
# Passed the open and close tags
# Returns the regular expression
sub tag_match(@)
{
    my ($open, $close) = @_;
    # Much of this regular expression stolen from Template::Mustache
    qr/
	(?<pre> .*?)		    # Text up to opening tag
	(?<tab> ^ \s*)?		    # Indent white space
	(?: \Q$open\E \s*)	    # Start of tag
	(?:
	    (?<type> =)   \s* (?<txt>.+?) \s* = |   # Change delimiters
	    (?<type> {)	  \s* (?<txt>.+?) \s* } |   # Unescaped
	    (?<type> &)	  \s* (?<txt>.+?)       |   # Unescaped
	    (?<type> \W?) \s* (?<txt>.+?)	    # Normal tags
	)
	(?: \s* \Q$close\E)	    # End of tag
    /xsm;
}

# Escape HTML entities
# Passed a string
# Returns an escaped string
sub escape($)
{
    my $_ = shift;
    s/&/&amp;/g;
    s/"/&quot;/g;
    s/</&lt;/g;
    s/>/&gt;/g;
    return $_;
}

# Reassemble the source code for an array of tags
# Passed an array of tags
# Returns the original source (roughly)
sub reassemble(@)
{
    my @tags = @_;
    my $last = pop @tags;
    my $ans = '';
    my $_;
    $ans .= "$_->{pre}$_->{tab}\{\{$_->{type}$_->{txt}\}\}" foreach (@tags);
    return $ans . $last->{pre};
}

#############################################################
##
##  Class Functions
##
##

=head1 METHODS

=head2 Creating a new Mustache::Simple object

=over

=item new

    my $tache = new Mustache::Simple(%options)

=back

=head3 Parameters:

=over

=item path

The path from which to load templates and partials.

Default: '.'

=item extension

The extension to add to filenames when reading them off disk. The
'.' should not be included as this will be added automatically.

Default: 'mustache'

=item throw

If set to a true value, Mustache::Simple will croak when there
is no key in the context hash for a given tag.

Default: undef

=item partial

This may be set to a subroutine to be called to generate the
filename or the template for a partial.  If it is not set, partials
will be loaded using the same parameters as render().

Default: undef

=back

=cut

sub new
{
    my $class = shift;
    my %options = @_ == 1 ? %{$_[0]} : @_;  # Allow a hash to be passed, in case
    my %defaults = (
	path	    => '.',
	extension   => 'mustache',
    );
    %options = (%defaults, %options);
    my $self = \%options;
    bless $self, $class;
}

#############################################################
##
##  Private Instance Functions
##
##

# Breaks the template into separate tags, preserving the text
# Returns an array ref of the tags and the trailing text
sub match_template
{
    my $self = shift;
    my $template = shift;
    my $match = tag_match(qw({{ }}));	# start with standard delimiters
    my @tags;
    my $afters;
    while ($template =~ /$match/g)
    {
	my %tag = %+;			# pick up named parts from the regex
	if ($tag{type} eq '=')		# change delimiters
	{
	    $match = tag_match(split /\s*/, $tag{txt});
	}
	else {
	    $afters = $';		# save off the rest in case it's done
	    push @tags, \%tag;		# put the tag into the array
	}
    }
    return \@tags, $template if (@tags == 0);	# no tags, it's all afters
    for (1 .. $#tags)
    {					# lose a leading LF after sections
	$tags[$_]->{pre} =~ s/^\n// if $tags[$_ - 1]->{type} =~ m{^[#/^]$};
    }
					# and from the trailing text
    $afters =~ s/^\n// if $tags[$#tags]->{type} eq '/';
    return \@tags, $afters;
}

# Performs partial includes
# Passed the current context, it calls the user code if any
# Returns the partial rendered in the current context
sub include_partial
{
    my $self = shift;
    my $context = shift;
    my $tag = shift;
    my $result;
    $tag = $self->partial->($tag) if (ref $self->partial eq 'CODE');
    $self->render($tag, $context);
}

# This is the main worker function.  It builds up the result from the tags.
# Passed the current context and the array of tags
# Returns the final text
# Note, this is called recursively, directly for sections and
# indirectly via render() for partials
sub resolve
{
    my $self = shift;
    my $context = shift;
    my @tags = @_;
    croak "Context must be a hash" unless ref $context eq 'HASH';
    my $result = '';
    for (my $i = 0; $i < @tags; $i++)
    {
	my $tag  = $tags[$i];			# the current tag
	$result .= $tag->{pre};			# add in the intervening text
	my $txt = $context->{$tag->{txt}};	# get the entry from the context
	given ($tag->{type})
	{
	    when(m{[!/]}) { break; }		# it's a comment - skip
	    when(/^[{&]?$/) {			# it's a variable
		if (defined $txt)
		{
		    $txt = "$tag->{tab}$txt" if $tag->{tab};	# replace the indent
		    $result .= /^[{&]$/ ? $txt : escape $txt;
		}
		elsif(!exists $context->{$tag->{txt}})
		{
		    croak qq(No context for "$tag->{txt}") if $self->throw;
		}
	    }
	    when('#') {				# it's a section start
		my $j;
		for ($j = $i + 1; $j < @tags; $j++) # find the end
		{
		    last if ($tags[$j]->{type} eq '/' &&
			$tag->{txt} eq $tags[$j]->{txt})
		}
		croak 'No end tag found for {{#'.$tag->{txt}.'}}' if $j == @tags;
		my @subtags =  @tags[$i + 1 .. $j]; # get the tags for the section
		given (ref $txt)
		{
		    when ('ARRAY') {	# an array of hashes (hopefully)
			$result .= $self->resolve($_, @subtags) foreach @$txt;
		    }
		    when ('CODE') {	# call user code which may call render()
			$self->push($context);
			$result .= $txt->(reassemble @subtags);
			$self->pop;
		    }
		    when ('HASH') {	# use the hash as context
			break unless scalar %$txt;
			$result .= $self->resolve($txt, @subtags);
		    }
		    default {		# resolve the tags in current context
			$result .= $self->resolve($context, @subtags) if $txt;
		    }
		}
		$i = $j;
	    }
	    when ('^') {		    # inverse section
		my $j;
		for ($j = $i + 1; $j < @tags; $j++)
		{
		    last if ($tags[$j]->{type} eq '/' &&
			$tag->{txt} eq $tags[$j]->{txt})
		}
		croak 'No end tag found for {{#'.$tag->{txt}.'}}' if $j == @tags;
		my @subtags =  @tags[$i + 1 .. $j];
		unless ($txt)		# resolve in current context
		{
		    $result .= $self->resolve($context, @subtags);
		}
		$i = $j;
	    }
	    when ('>') {		# partial - see include_partial()
		$result .= $self->include_partial($context, $tag->{txt});
	    }
	    default {			# allow for future expansion
		croak "Unknown tag type in \{\{$_$tag->{txt}}}";
	    }
	}
    }
    return $result;
}

# Push something (usually a context) onto the stack
sub push
{
    my $self = shift;
    my $value = shift;
    my @stack;
    $self->{stack} = \@stack unless $self->{stack};
    my $stack = $self->{stack};
    push @$stack, $value;
}

# Pop the context back off the stack
sub pop
{
    my $self = shift;
    my $stack = $self->{stack};
    return pop @$stack;
}

# Retrieve the top item from the stack
sub top
{
    my $self = shift;
    my $value = $self->pop;
    $self->push($value);
    return $value;
}

#############################################################
##
##  Public Instance Functions
##
##

use constant functions => qw(path extension throw partial);

=head2 Configuration Methods

The configuration methods match the %options array thay may be passed
to new().

Each option may be called with a non-false value to set the option
and will return the new value.  If called without a value, it will return
the current value.

=over

=item path()

    $tache->path('/some/new/template/path');
    my $path = $tache->path;	# defaults to '.'

=item extension()

    $tache->extension('html');
    my $extension = $tache->extension;	# defaults to 'mustache'

=item throw()

    $tache->throw(1);
    my $throwing = $tache->throw;	# defaults to undef

=item partial()

    $tache->partial(\&resolve_partials)
    my $partial = $tache->partial	# defaults to undef

=back

=cut

sub AUTOLOAD
{
    my $self = shift;
    my $class = ref $self;
    my $value = shift;
    (my $name = our $AUTOLOAD) =~ s/.*:://;
    my %ok = map { ($_, 1) } functions;
    croak "Unknown function $class->$name()" unless $ok{$name};
    $self->{$name} = $value if $value;
    return $self->{$name};
}

# Prevent it being caught by AUTOLOAD
sub DESTROY
{
}

=head2 Instance methods

=over

=item read_file()

    my $template = read_file('templatefile');

You will not usually need to call this directly as it's called by
L</render> to load the file.  If it is passed a string that looks like
a template (i.e. has {{ in it) it simply returns it.  Similarly, if,
after prepending the path and adding the suffix, it cannot load the file,
it simply returns the original string.

=back

=cut

sub read_file($)
{
    my $self = shift;
    my $file = shift;
    return undef if $file =~ /{{/;
    my $extension = $self->extension;
    $file =~ s/(\.$extension)?$/.$extension/;
    $file = File::Spec->catfile($self->path, $file);
    local $/;
    open my $hand, "<:utf8", $file or croak "Can't open $file: $!";
    <$hand>;
}

=over

=item render()

    my $context = {
	"name" => "Chris",
	"value" => 10000,
	"taxed_value" => 10000 - (10000 * 0.4),
	"in_ca" => true
    }
    my $html = $tache->render('templatefile', $context);

This is the main entry-point for rendering templates.  It can be passed
either a full template or path to a template file.  See L</read_file>
for details of how the file is loaded.  It must also be passed a hashref
containing the main context.

In callbacks (sections like C< {{#this}} > with a subroutine in the context),
you may call render on the passed string and the current context will be
remembered.  For example:

    {
	name => "Willy",
	wrapped => sub {
	    my $text = shift;
	    chomp $text;
	    return "<b>" . $tache->render($text) . "</b>\n";
	}
    }

Alternatively, you may pass in an entirely new context when calling
render() from a callback.

=back

=cut

sub render
{
    my $self = shift;
    my ($template, $context) = @_;
    $context = $self->top unless $context;
    $template = $self->read_file($template) || $template;
    my ($tags, $tail) = $self->match_template($template);
    # print reassemble(@$tags), $tail; exit;
    my $result = $self->resolve($context, @$tags) . $tail;
}

=head1 EXPORTS

Nothing.

=head1 SEE ALSO

L<Template::Mustache|Template::Mustache> - a much more complex module that is
designed to be subclassed for each template.

=head1 AUTHOR INFORMATION

Cliff Stanford C<< <cliff@may.be> >>

=head1 LICENCE AND COPYRIGHT

Copyright © 2012, Cliff Stanford C<< <cliff@may.be> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;

