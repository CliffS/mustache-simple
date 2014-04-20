#!/usr/bin/perl

use strict;
use warnings;
use 5.10.0;

use lib '/home/cliff/src/git/mustache-simple/lib';
use Mustache::Simple;
use enum qw{ false true };

my $data = {
    a =>  { one =>  1 },
    b =>  { two =>  2 },
    c =>  { three =>  3 },
    d =>  { four =>  4 },
    e =>  { five =>  5 },
};

my $template = <<EOT;
{{#a}}
{{one}}
{{#b}}
{{one}}{{two}}{{one}}
{{#c}}
{{one}}{{two}}{{three}}{{two}}{{one}}
{{#d}}
{{one}}{{two}}{{three}}{{four}}{{three}}{{two}}{{one}}
{{#e}}
{{one}}{{two}}{{three}}{{four}}{{five}}{{four}}{{three}}{{two}}{{one}}
{{/e}}
{{one}}{{two}}{{three}}{{four}}{{three}}{{two}}{{one}}
{{/d}}
{{one}}{{two}}{{three}}{{two}}{{one}}
{{/c}}
{{one}}{{two}}{{one}}
{{/b}}
{{one}}
{{/a}}
EOT

my $data1 = { section => true, data => 'I got interpolated.' };
my $template1 = <<EOT;
[
{{#section}}
{{data}}
|data|
{{/section}}

|#section|
{{data}}
|data|
|/section|
]
EOT

my $template2 = q(
{{#outer}}{{one}}{{#inner}}{{one}}{{two}}{{/inner}}{{/outer}}
);
my $data2 = {
    outer => {
	inner => {
	    two => 2
	},
	one => 1,
    }
};

my $mus = new Mustache::Simple;
say $mus->render($template2, $data2);
