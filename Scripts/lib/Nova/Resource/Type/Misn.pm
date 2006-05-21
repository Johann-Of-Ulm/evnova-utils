# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Misn;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('misn');

use Nova::Resource::Spec::Spob;
use Nova::Resource::Spec::Syst;

sub fullName {
	my ($self) = @_;
	my $name = $self->SUPER::fullName;
	if ($name =~ /^(.*);\s*(.*)$/) {
		return "$2: $1";
	} else {
		return $name;
	}
}

sub show {
	my ($self, $verb) = @_;
	my $ret = $self->SUPER::show($verb);
	
	$ret .= $self->showField($_, $verb) for qw(
		AvailStel AvailLoc AvailRecord AvailRating AvailRandom
		AvailShipType AvailBits OnSuccess
	);
	
	if ($verb) {
		$ret .= "\n";
		my $where = ''; 
		for my $field (qw(TravelStel ReturnStel ShipSyst)) {
			my $s = $self->showField($field, $verb);
			$where = "\n" if $s;
			$ret .= $s;
		}
		$ret .= $where;
			
		$ret .= $self->showField($_, $verb) for qw(
			InitialText RefuseText BriefText QuickBrief
			LoadCargText ShipDoneText DropCargText CompText FailText);
	}
		
	return $ret;
}

sub showFieldByName {
	my ($self, $field, $verb) = @_;
	if ($field =~ /(Text|Brief)$/) {
		return $self->showText($field, $verb);
	} elsif ($field =~ /Stel$/) {
		return $self->showStelSpec($field, $verb);
	} else {
		return $self->SUPER::showFieldByName($field, $verb);
	}
}

sub fieldDefaults {
	return (
		AvailRecord		=> 0,
		AvailRating		=> [ 0, -1 ],
		AvailRandom		=> 100,
		AvailShipType	=> [ 0, -1 ],
		ShipCount		=> [ 0, -1 ],
		AvailLoc		=> 1,
	);
}

sub showStelSpec {
	return Nova::Resource::Spec::Spob->new(@_[0,1])->dump($_[2] > 2);
}

sub showText {
	my ($self, $field, $verb) = @_;
	my $descid = $self->field($field);
	if ($descid < 128) {
		return $verb < 2 ? '' : "$field: $descid\n";
	}
	my $desc = $self->collection->get(desc => $descid);
	my $text = $desc->Description;
	return "$field: $text\n\n";
}

# Fake field
sub initialText { $_[0]->ID + 4000 - 128 }

sub showShipSyst {
	my ($self, $field, $verb) = @_;
	unless (defined ($self->fieldDefined('shipCount'))) {
		return $verb < 2 ? '' : "$field: none\n";
	}
	return Nova::Resource::Spec::Syst->new($self, $field)->dump($verb > 2);
}

sub showAvailLoc {
	my ($self, $field, $verb) = @_;
	my $val = $self->field($field);
	return '' if $verb < 2 && !defined($self->fieldDefined($field));
	
	my %locations = (		0 => 'mission computer',	1 => 'bar',
		2 => 'pers',		3 => 'main spaceport',		4 => 'commodities',
		5 => 'shipyard',	6 => 'outfitters');
	return "$field: $locations{$val}\n";
}

1;
