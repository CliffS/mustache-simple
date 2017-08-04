BEGIN {
        use Test::More qw(no_plan);
        use_ok('Mustache::Simple','load module Mustache::Simple');
}

my $testbook = TestClass::Book->new(
    author => "Ed Editor",
    title => "A Book with Chapters",
    chapters => [
	TestClass::Chapter->new(
	    author => "Alice Able",
	    title => "About Arithmetic And Algebra"),
	TestClass::Chapter->new(
	    author => "Bob Baker",
	    title => "Before Boston Broke"),
	TestClass::Chapter->new(
	    author => "Carol Craft",
	    title => "Crunching Capital Concerns")
	],
    appendices => [
	{ title => "First Appendix" },
	{ title => "Second Appendix" },
    ],
    awards_won => [],
    );

is($testbook->author,"Ed Editor","retrieve book's author");
is($testbook->author,$testbook->editor,"editor is alias for author");
is(($testbook->chapters())[0]->author,"Alice Able","get first chapter with ()[0]");
is(scalar($testbook->chapters()),3,"in scalar context num chapters");

my $template = q[
Table of contents for {{title}}
{{editor}}, ed.
-------------------------------
{{#chapters}}
{{author}}, "{{title}}"
{{/chapters}}
Appendices:
{{#appendices}}
{{title}}
{{/appendices}}
];

my $expected = q[
Table of contents for A Book with Chapters
Ed Editor, ed.
-------------------------------
Alice Able, "About Arithmetic And Algebra"
Bob Baker, "Before Boston Broke"
Carol Craft, "Crunching Capital Concerns"
Appendices:
First Appendix
Second Appendix
];

my $mustache = Mustache::Simple->new();
my $result = $mustache->render($template,$testbook);
is($result,$expected,"nested section template renders as expected");

is($mustache->render(
	q[{{#editor}}has an editor{{/editor}}],$testbook),
	    q[has an editor],'non-array method used in # section as boolean true');

is($mustache->render(
       q[{{^editor}}has no editor{{/editor}}],$testbook),
   q[],'non-array method used in ^ section as boolean true');

is($mustache->render(
       q[{{^chapters}}has no chapters{{/chapters}}],$testbook),
   q[],'array method used in ^ section as boolean true');

is($mustache->render(
       q[{{^awards_won}}won no awards{{/awards_won}}],$testbook),
   q[won no awards],'array method used in ^ section as boolean false');

# These tests do not work this way,
isnt($mustache->render(
       q[This book has {{chapters}} chapters],$testbook),
   q[This book has 3 chapters],'array method in non-section returns num elts of array?');

# but they fail to work this way for regular old arrayrefs too
my $testhash = { anarray => [ 'one','two' ] };
isnt($mustache->render(
       q[This list has {{anarray}} elements],$testhash),
   q[This list has 2 elements],'array ref in non-section returns num elts of array?');

# TODO
# why do the previous two tests fail with different output?
#
#  TestClass::Chapter=HASH(0x802eb0768) 
#   vs
#  ARRAY(0x802ecfd68)
#
# Obviously in the first case my code that returns the first item when called
# in scalar context is the culprit.

package TestClass::Publication;
sub new {
    my $class = shift;
    my %args = @_;
    return bless(\%args,$class);
}
sub author { shift->{author} };
sub title  { shift->{title} };

package TestClass::Book;
use base TestClass::Publication;
sub editor { shift->{author} }; # editor is an alias for author of a book
sub chapters   { @{ shift->{chapters}   } };
sub appendices { @{ shift->{appendices} } };
sub awards_won { @{ shift->{awards_won} } };

package TestClass::Chapter;
use base TestClass::Publication;

