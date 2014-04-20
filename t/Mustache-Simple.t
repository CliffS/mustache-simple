# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Mustache-Simple.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;
use 5.10.0;

use YAML::XS qw(LoadFile);
use Data::Dumper;

use Test::More; # tests => 1;
BEGIN { use_ok('Mustache::Simple') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my @tests;
push @tests, LoadFile($_) foreach (glob 't/specs/*.yml');

# print STDERR Dumper @tests;

my @skip = (
    'Indented Inline',
    'Standalone Without Newline',
    'Standalone Without Previous Line',
    qr{Decimal},
    'Internal Whitespace',
    'Indented Inline Sections',
    'Standalone Line Endings',
    'Standalone Indentation',
    'Standalone Indented Lines',

);


foreach my $yaml (@tests)
{
    foreach my $test (@{$yaml->{tests}})
    {
#	say STDERR "Test: $test->{name}";
	SKIP: {
	    foreach (@skip)
	    {
		skip $test->{name}, 1 if $test->{name} ~~ $_;
	    }
	    eval {
		my $mustache = new Mustache::Simple(
		    partial => sub {
			my $partial = shift;
			return $test->{partials}{$partial};
		    },
		);
		my $context = $test->{data};
		if (exists $context->{lambda}{perl})
		{
		    $context->{lambda} = eval $context->{lambda}{perl};
		}
		my $result = $mustache->render($test->{template}, $test->{data});
		is($result, $test->{expected}, $test->{desc});
	    };
	    fail($test->{name} . ": $@") if $@;
	}
    }
}

done_testing();

