# Copyright (c) 2006 Dave Vasilevsky
package Nova::Command::ConText;
use strict;
use warnings;

use base 'Nova::Command';
use Nova::Command qw(command);

=head1 NAME

Nova::Command::ConText - commands related to ConText files

=cut

command {
	my ($self, $val) = @_;
	$self->config->conText($val) if defined $val;
	printf "%s\n", $self->config->conText;
} 'context' => 'get/set the ConText file';


=head1 NAME

Nova::Command::ConText::Using - commands that use the contents of the
default ConText file

=cut

package Nova::Command::ConText::Using;
use base 'Nova::Command::ConText';
__PACKAGE__->fields(qw(resources));

use Nova::ConText;
use Nova::Command qw(command);

use Nova::Util qw(prettyPrint);
use Nova::Columns;

# Load the current context file
sub _loadContext {
	my ($self) = @_;
	my $ct = Nova::ConText->new($self->config->conText);
	$self->resources($ct->read);
	$self->resources->readOnly;
}

sub setup {
	my ($self) = @_;
	$self->SUPER::setup;
	$self->_loadContext;
}

command {
	my ($self) = @_;
	$self->resources->deleteCache;
	$self->_loadContext;
} reload => 'reload the ConText';

command {
	my ($self, $type, $spec, @fields) = @_;
	print $self->resources->find($type => $spec)->dump(@fields);
} 'dump' => 'dump a resource';

command {
	my ($self, $type, @specs) = @_;
	my @res = $self->resources->find($type => @specs);
	my $verb = $self->config->verbose;
	
	# Could take a while, so display incrementally
	for my $i (0..$#res) {
		prettyPrint $res[$i]->show($verb);
		print "\n" x ($verb + 1) if $i != $#res;
	}
} show => 'display a resource nicely';

command {
	my ($self, @types) = @_;
	columns('%s %d: %-s', [ $self->resources->type(@types) ],
		sub { $_->type, $_->ID, $_->fullName });
} listAll => 'list all known resources of the given types';

command {
	my ($self, $type, @specs) = @_;
	columns('%d: %-s', [ $self->resources->find($type => @specs) ],
		sub { $_->ID, $_->fullName });
} list => 'list resources matching a specification';

command {
	my ($self, $spec) = @_;
	my $ship = $self->resources->find(ship => $spec);
	$ship->mass(1);
} mass => 'show the total mass available on a ship';

command {
	my ($self, $type, $prop) = @_;
	($type, $prop) = ('ship', $type) unless defined $prop;
	
$DB::single = 1;
	columns('%s - %d: %-<s  %?s', [ $self->resources->type($type) ],
		sub { $_->format($prop), $_->ID, $_->fullName, $_->rankInfo($prop) },
		rank => sub { $_->$prop }
	);
} rank => 'rank resources by a property';

command {
	my ($self, $bit) = @_;
	my @data;
	
	my $rs = $self->resources;
	for my $t ($rs->types) {
		my @rs = $rs->type($t);
		next unless @rs;
		my @flds = $rs[0]->bitFields;
		next unless @flds;
		
		for my $fld (@flds) {
			my @match = grep { $_->filter($fld, sub { $_ }) } @rs;
			my $dispType = $fld eq $flds[0] ? $t : '';
			push @data, [ $dispType, $fld, scalar(@match) ];
		}
	}
	columns('%s  %-s  %s', \@data, sub { @$_ });
} bit => 'find items which use a given bit';

command {
	my ($self, $type, $prop, $filt) = @_;
	my @rs = $self->resources->type($type);
	
	# Filter
	if (defined $filt) {
		my $filtCode = Nova::Resource->makeFilter($filt);
		@rs = grep { $_->filter($prop, $filtCode) } @rs;
	}
	
	columns('%d: %-<s   %?s', \@rs,
		sub { $_->ID, $_->fullName, $_->format($prop) });
} 'map' => 'show a single property of each resource'; 


1;
