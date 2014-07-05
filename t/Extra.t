

use strict;
use warnings;
use 5.10.0;

use Test::More tests => 1;
use Mustache::Simple;


my $data = {
    customer => {
	name	=> 'fred',
	address	=> 'line 1 <br/> line 2',
    }
};

my $template = '{{{customer.address}}}';

my $mus = new Mustache::Simple;
my $result = $mus->render($template, $data);

is($result, 'line 1 <br/> line 2', '{{{ with dot');


