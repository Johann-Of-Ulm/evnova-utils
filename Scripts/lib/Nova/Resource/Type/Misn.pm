# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Misn;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;

use Nova::Resource::Spec::Spob;
use Nova::Resource::Spec::Syst;
use Nova::Resource::Spec::Ship;
use Nova::Util qw(wrap);

flagInfo('Flags',
	autoAbort		=> 'auto-abort',
	arrowNoDest		=> "don't show destination arrow",
	noRefuse		=> "can't refuse",
	useFuel			=> 'takes 100 fuel on auto-abort',
	infiniteShips	=> 'infinite aux ships',
	failScan		=> 'fail if scanned',
	penaltyAbort	=> 'apply -5 x CompReward penalty on abort',
	(undef, undef),
	arrowBrief		=> 'show green arrow in briefing',
	arrowShipSyst	=> 'show arrow at ship syst',
	invisible		=> 'invisible',
	keepType		=> 'special ship type kept the same',
	shipNoCargo		=> 'unavailable if in a cargo ship',
	shipNoCombat	=> 'unavailable if in a combat ship',
	failBoard		=> 'fail if boarded by pirates',
);

flagInfo('Flags2',
	checkSpace		=> "require sufficient cargo space",
	payAbort		=> 'pay on auto-abort',
	failDead		=> 'fail if disabled or destroyed',
);

sub fullName {
	my ($self) = @_;
	my $name = $self->NEXT::fullName;
	if ($name =~ /^(.*);\s*(.*)$/) {
		return "$2: $1";
	} else {
		return $name;
	}
}

sub show {
	my ($self, $verb, @fields) = @_;
	my $ret = $self->NEXT::show($verb, @fields);
	return $ret if @fields;
	
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

sub formatByName {
	my ($self, $field, $verb) = @_;
	if ($field =~ /(Text|Brief)$/) {
		return $self->formatText($field, $verb);
	} elsif ($field =~ /Stel$/) {
		return $self->formatStelSpec($field, $verb);
	} else {
		return $self->NEXT::formatByName($field, $verb);
	}
}

sub showByName {
	my ($self, $field, $verb) = @_;
	if ($field =~ /(Text|Brief)$/) {
		return $self->showText($field, $verb);
	} else {
		return $self->NEXT::showByName($field, $verb);
	}
}

sub fieldDefaults {
	return (
		AvailRecord		=> 0,
		AvailRating		=> [ -1, 0 ],
		AvailRandom		=> 100,
		ShipCount		=> [ -1, 0 ],
		AvailLoc		=> 1,
		CargoQty		=> -1,
	);
}

sub formatStelSpec {
	return Nova::Resource::Spec::Spob->new(@_[0,1])->desc;
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

sub formatShipSyst {
	my ($self, $field, $verb) = @_;
	unless (defined ($self->fieldDefined('shipCount'))) {
		return $verb < 2 ? '' : 'none';
	}
	return Nova::Resource::Spec::Syst->new($self, $field)->desc;
}

sub formatAvailLoc {
	my ($self, $field, $verb) = @_;
	my $val = $self->field($field);
	return '' if $verb < 2 && !defined($self->fieldDefined($field));
	
	my %locations = (		0 => 'mission computer',	1 => 'bar',
		2 => 'pers',		3 => 'main spaceport',		4 => 'commodities',
		5 => 'shipyard',	6 => 'outfitters');
	return $locations{$val};
}

sub importantBitFields { $_[0]->bitFields }

sub _spobSystCache {
	$_[0]->precalc(spobSyst => sub {
		my ($self, $cache) = @_;
		for my $syst (reverse $self->collection->type('syst')) {
			for my $spob ($syst->spobs) {
				$cache->{$spob->ID} = $syst->ID;
			}
		}
	});
}

sub persons {
	my ($self) = @_;
	
	my $id = $self->ID;
	my $c = $self->precalc(misnPers => sub {
		my ($self, $cache) = @_;
		for my $pers ($self->collection->type('pers')) {
			if (defined(my $mid = $pers->fieldDefined('LinkMission'))) {
				push @{$cache->{$mid}}, $pers->ID;
			}
		}
	});
	return exists $c->{$id}
		? map { $self->collection->get(pers => $_) } @{$c->{$id}}
		: ();
}

sub shipType {
	my ($self) = @_;
	return Nova::Resource::Spec::Ship->new($self, 'AvailShipType');
}

sub formatAvailShipType {
	my ($self, $field, $verb) = @_;
	return $self->shipType->desc;
}

sub showPersons {
	my ($self, $verb) = @_;
	my @persons = $self->persons;
	return '' unless @persons;
	
	my $ret = sprintf "%d: %s\n", $self->ID, $self->fullName;
	for my $field (qw(AvailRecord AvailRating AvailRandom AvailShipType
			AvailBits CargoQty CheckSpace)) {
		my $s = $self->showField($field, $verb);
		$ret .= "  $s" if $s;
	}
	
	# FIXME: AI types
	
	# Print pers for this mission
	if ($verb) {
		my %descs;
		for my $pers (@persons) {
			my $desc = $pers->show($verb);
			(my $head, $desc) = ($desc =~ /^(.*?\n)(.*)$/s);
			push @{$descs{$desc}}, $pers;
		}
		for my $desc (sort { $descs{$a}[0]->ID <=> $descs{$b}[0]->ID }
				keys %descs) {
			for my $pers (@{$descs{$desc}}) {
				$ret .= '  ' . sprintf "%d: %s\n", $pers->ID, $pers->fullName;
			}
			$desc =~ s/^/    /mg;
			$ret .= $desc;
		}
	}
	
	return $ret;
}

1;
