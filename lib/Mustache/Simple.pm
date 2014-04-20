package Mustache::Simple;

use strict;
use warnings;
use 5.10.0;
use utf8;

# Don't forget to change the version in the pod
our $VERSION = v1.2.0;

use File::Spec;
use Mustache::Simple::ContextStack;

use Carp;

use Data::Dumper;
$Data::Dumper::Useqq = 1;
$Data::Dumper::Deparse = 1;

=encoding utf8

=head1 NAME

Mustache::Simple - A simple Mustach Renderer

See L<http://mustache.github.com/>.

=head1 VERSION

This document describes Mustache::Simple version 1.2.0

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

As of version 1.2.0, it has support for nested contexts, for the dot notation
and for the implicit iterator.

=head2 Rationale

I wanted a simple rendering tool for Mustache that did not require any
subclassing.

=cut


#############################################################
##
##  Helper Functions
##
##

sub dottags($)
{
    my $tag = shift;
    my @dots = $tag =~ /(.*?)\.(.*)/;
    my @tags = (
	{ pre => '', type => '#', txt => $dots[0] },
	{ pre => '', type => '',  txt => $dots[1] },
	{ pre => '', type => '/', txt => $dots[0] },
    );
    return @tags;
}

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
	    (?<type> [#^>\/!]?) \s* (?<txt>.+?)	    # Normal tags
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
    no warnings 'uninitialized';
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

The path from which to load templates and partials. This may be
a string or a reference to an array of strings.  If it is a reference,
each string will be searched in order.

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
	delimiters  => [qw({{ }})],
	stack	    => new Mustache::Simple::ContextStack,
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
    my $match = tag_match(@{$self->{delimiters}});	# start with standard delimiters
    my @tags;
    my $afters;
    while ($template =~ /$match/g)
    {
	my %tag = %+;			# pick up named parts from the regex
	if ($tag{type} eq '=')		# change delimiters
	{
	    my @delimiters = split /\s/, $tag{txt};
	    $self->{delimiters} = \@delimiters;
	    $match = tag_match(@delimiters);
	}
	$afters = $';		# save off the rest in case it's done
	push @tags, \%tag;		# put the tag into the array
    }
    return \@tags, $template if (@tags == 0);	# no tags, it's all afters
    for (1 .. $#tags)
    {					# lose a leading LF after sections
	$tags[$_]->{pre} =~ s/^\r?\n// if $tags[$_ - 1]->{type} =~ m{^[#/^]$};
    }
    if (@tags > 1)
    {
	$tags[1]->{pre} =~ s/^\r?\n// if $tags[0]->{type} eq '=' and $tags[0]->{pre} =~ /^\s*$/;
    }
    foreach(0 .. $#tags)
    {
	$tags[$_]->{pre} =~ s/^\r?\n// if $tags[$_]->{type} =~ m{^[!]$};
	$tags[$_]->{pre} =~ s/\r?\n$// if $tags[$_]->{type} =~ m{^[=]$};
    }
					# and from the trailing text
    $afters =~ s/^\r?\n// if $tags[$#tags]->{type} =~ m{^[/!]$};
    return \@tags, $afters;
}

# Performs partial includes
# Passed the current context, it calls the user code if any
# Returns the partial rendered in the current context
sub include_partial
{
    my $self = shift;
    my $tag = shift;
    my $result;
    $tag = $self->partial->($tag) if (ref $self->partial eq 'CODE');
    $self->render($tag);
}

# This is the main worker function.  It builds up the result from the tags.
# Passed the current context and the array of tags
# Returns the final text
# Note, this is called recursively, directly for sections and
# indirectly via render() for partials
sub resolve
{
    my $self = shift;
    my $context = shift // {};
    $self->push($context);
    my @tags = @_;
    my $result = '';
    for (my $i = 0; $i < @tags; $i++)
    {
	my $tag  = $tags[$i];			# the current tag
	$result .= $tag->{pre};			# add in the intervening text
	given ($tag->{type})
	{
	    when('!') {				# it's a comment
		# $result .= $tag->{tab} if $tag->{tab};
	    }
	    when('/') { break; }		# it's a section end - skip
	    when('=') { break; }		# delimiter change
	    when(/^([{&])?$/) {			# it's a variable
		my $txt;
		if ($tag->{txt} eq '.')
		{
		    $txt = $self->{stack}->top;
		}
		elsif ($tag->{txt} =~ /\./)
		{
		    my @dots = dottags $tag->{txt};
		    $txt = $self->resolve(undef, @dots);
		}
		else {
		    $txt = $self->find($tag->{txt});	# get the entry from the context
		    if (defined $txt)
		    {
			if (ref $txt eq 'CODE')
			{
			    my $saved = $self->{delimiters};
			    $self->{delimiters} = [qw({{ }})];
			    $txt = $self->render(&$txt());
			    $self->{delimiters} = $saved;
			}
		    }
		    else {
			croak qq(No context for "$tag->{txt}") if $self->throw;
			$txt = '';
		    }
		}
		$txt = "$tag->{tab}$txt" if $tag->{tab};	# replace the indent
		$result .= $tag->{type} ? $txt : escape $txt;
	    }
	    when('#') {				# it's a section start
		my $j;
		my $nested = 0;
		for ($j = $i + 1; $j < @tags; $j++) # find the end
		{
		    if ($tag->{txt} eq $tags[$j]->{txt})
		    {
			$nested++, next if $tags[$j]->{type} eq '#';	# nested sections with the
			if ($tags[$j]->{type} eq '/')			#   same name
			{
			    next if $nested--;
			    last;
			}
		    }
		}
		croak 'No end tag found for {{#'.$tag->{txt}.'}}' if $j == @tags;
		my @subtags =  @tags[$i + 1 .. $j]; # get the tags for the section
		my $txt;
		if ($tag->{txt} =~ /\./)
		{
		    my @dots = dottags($tag->{txt});
		    $txt = $self->resolve(undef, @dots);
		}
		else {
		    $txt = $self->find($tag->{txt});	# get the entry from the context
		}
		given (ref $txt)
		{
		    when ('ARRAY') {	# an array of hashes (hopefully)
			$result .= $self->resolve($_, @subtags) foreach @$txt;
		    }
		    when ('CODE') {	# call user code which may call render()
			$result .= $self->render($txt->(reassemble @subtags));
		    }
		    when ('HASH') {	# use the hash as context
			break unless scalar %$txt;
			$result .= $self->resolve($txt, @subtags);
		    }
		    default {		# resolve the tags in current context
			$result .= $self->resolve(undef, @subtags) if $txt;
		    }
		}
		$i = $j;
	    }
	    when ('^') {		    # inverse section
		my $j;
		my $nested = 0;
		for ($j = $i + 1; $j < @tags; $j++)
		{
		    if ($tag->{txt} eq $tags[$j]->{txt})
		    {
			$nested++, next if $tags[$j]->{type} eq '^';	# nested sections with the
			if ($tags[$j]->{type} eq '/')			#   same name
			{
			    next if $nested--;
			    last;
			}
		    }
		}
		croak 'No end tag found for {{#'.$tag->{txt}.'}}' if $j == @tags;
		my @subtags =  @tags[$i + 1 .. $j];
		my $txt;
		if ($tag->{txt} =~ /\./)
		{
		    my @dots = dottags($tag->{txt});
		    $txt = $self->resolve(undef, @dots);
		}
		else {
		    $txt = $self->find($tag->{txt});	# get the entry from the context
		}
		my $ans = '';
		given (ref $txt)
		{
		    when ('ARRAY') {
			$ans = $self->resolve(undef, @subtags) if @$txt == 0;
		    }
		    when ('HASH') {
			$ans = $self->resolve(undef, @subtags) if keys %$txt == 0;
		    }
		    default {
			$ans = $self->resolve(undef, @subtags) unless $txt;
		    }
		}
		$ans =  "$tag->{tab}$ans" if $tag->{tab};	# replace the indent
		$result .= $ans;
		$i = $j;
	    }
	    when ('>') {		# partial - see include_partial()
		my $saved = $self->{delimiters};
		$self->{delimiters} = [qw({{ }})];
		$result .= $self->include_partial($tag->{txt});
		$self->{delimiters} = $saved;
	    }
	    default {			# allow for future expansion
		croak "Unknown tag type in \{\{$_$tag->{txt}}}";
	    }
	}
    }
    $self->pop;
    return $result;
}

# Push something a context onto the stack
sub push
{
    my $self = shift;
    my $value = shift;
    $self->{stack}->push($value);
}

# Pop the context back off the stack
sub pop
{
    my $self = shift;
    my $value = $self->{stack}->pop;
    return $value;
}

# Find a value on the stack
sub find
{
    my $self = shift;
    my $value = shift;
    return $self->{stack}->search($value);
}

# Given a path and a filename
# returns the first match that exists
sub getfile($$);
sub getfile($$)
{
    my ($path, $filename) = @_;
    $filename =~ s/\r?\n$//; # not chomp $filename because of the possibility of \r\n
    return if $filename =~ /\r?\n/;
    my $fullfile;
    if (ref $path && ref $path eq 'ARRAY')
    {
	foreach (@$path)
	{
	    $fullfile = getfile $_, $filename;
	    last if $fullfile;
	}
    }
    else {
	$fullfile = File::Spec->catfile($path, $filename);
	undef $fullfile unless -e $fullfile;
    }
    return $fullfile;
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
or
    $tache->path([ qw{/some/new/template/path .} ]);
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
    return '' unless $file;
    return $file if $file =~ /{{/;
    my $extension = $self->extension;
    (my $fullfile = $file) =~ s/(\.$extension)?$/.$extension/;
    my $filepath = getfile $self->path, $fullfile;
    return $file unless $filepath;
    local $/;
    open my $hand, "<:utf8", $filepath or croak "Can't open $filepath: $!";
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
    $context = {} unless $context;
    $template = $self->read_file($template);
    my ($tags, $tail) = $self->match_template($template);
    # print reassemble(@$tags), $tail; exit;
    my $result = $self->resolve($context, @$tags) . $tail;
    return $result;
}

=head1 COMPLIANCE WITH THE STANDARD

The original standard for Mustache was defined at the
L<Mustache Manual|http://mustache.github.io/mustache.5.html>
and this version of L<Mustache::Simple> was designed to comply
with just that.  Since then, the standard for Mustache seems to be
defined by the L<Mustache Spec|https://github.com/mustache/spec>.

The test suite on this version skips a number of tests
in the Spec, all of which relate to Decimals or White Space.
It passes all the other tests. The YAML from the Spec is built
into the test suite.

=head1 BUGS

=over

=item White Space

Much of the more esoteric white-space handling specified in
L<The Mustache Spec|https://github.com/mustache/spec> is not strictly adhered to
in this version.  Most of this will be addressed in a future version.

Because of this, the following tests from the Mustache Spec are skipped:

=over

=item * Indented Inline

=item * Indented Inline Sections

=item * Internal Whitespace

=item * Standalone Indentation

=item * Standalone Indented Lines

=item * Standalone Line Endings

=item * Standalone Without Newline

=item * Standalone Without Previous Line

=back

=item Decimal Interpolation

The spec implies that the template C<"{{power}} jiggawatts!"> when passed
C<{ power: "1.210" }> should return C<"1.21 jiggawatts!">.  I believe this to
be wrong and simply a mistake in the YAML of the relevant tests or possibly
in L<YAML::XS>. I am far from being a YAML expert.

Clearly C<{ power : 1.210 }> would have the desired effect.

Because of this, all tests matching C</Decimal/> have been skipped.  We can just
assume that Perl will do the right thing.

=back

=head1 EXPORTS

Nothing.

=head1 SEE ALSO

L<Template::Mustache|Template::Mustache> - a much more complex module that is
designed to be subclassed for each template.

=head1 AUTHOR INFORMATION

Cliff Stanford C<< <cliff@may.be> >>

=head1 SOURCE REPOSITORY

The source is maintained at a public Github repositor at
L<https://github.com/CliffS/mustache-simple>.  Feel free to fork
it and to help me fix some of the above issues. Please leave any
bugs or issues on the L<Issues|https://github.com/CliffS/mustache-simple/issues>
page and I will be notified.

=head1 LICENCE AND COPYRIGHT

Copyright © 2014, Cliff Stanford C<< <cpan@may.be> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;

