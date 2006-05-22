﻿# Copyright (c) 2006 Dave Vasilevsky

package Nova::Util;
use strict;
use warnings;

use base qw(Exporter);

use List::Util qw(max min sum);
use Text::Wrap qw();

our @EXPORT_OK = qw(deaccent commaNum termWidth columns wrap prettyPrint);

=head1 NAME

Nova::Util - Miscellaneous utilities

=head1 SYNOPSIS

  my $str = deaccent($str);
  my $str = commaNum($num);
  my $width = termWidth;

=cut

# $str = deaccent($str);
#
# Remove accents from a resource type, and canonicalizes is to lower-case.
# Eg: mïsn => misn
sub deaccent {
	my ($s) = @_;
	$s =~ tr/\x{e4}\x{eb}\x{ef}\x{f6}\x{fc}\x{ff}/aeiouy/;
	return lc $s;
}

# Get the comma-delimited form of the given number. Eg: 1234567 => 1,234,567
sub commaNum {
	my ($n) = @_;
	return $n if $n < 1000;
	return commaNum(int($n/1000)) . sprintf ",%03d", $n % 1000;
}

# Get the width of the terminal
sub termWidth {
	if (eval { require Fink::CLI }) {
		return Fink::CLI::get_term_width();
	} elsif (exists $ENV{COLUMNS}) {
		return $ENV{COLUMNS};
	} else {
		return 80;
	}
}

# my $pct = _columnFormats($wholeFmt, \@fmts, \@data, %opts);
#
# Get the percent-formats
sub _columnFormats {
	my ($wholeFmt, $fmts, $data, @opts) = @_;
	my %opts = (truncMin => 5, @opts);
	
	# Find the columns
	my (@cols, @lens);
	for my $i (0..$#$fmts) {
		my @col = map { $_->{cols}[$i] } @$data;
		push @cols, \@col;
		push @lens, max map { length($_) } @col;
	}
	(my $justText = $wholeFmt) =~ s/%\d+\w//g;
	my $width = termWidth() - sum(@lens) - length($justText);
	
	# Process each format
	for my $i (0..$#$fmts) {
		my $fmt = $fmts->[$i];
		if ($fmt =~ /</) {
			my $len = min($lens[$i], max($width + $lens[$i], $opts{truncMin}));
			$fmt =~ s/</$len.$len/;
		} else {
			$fmt .= $lens[$i];
		}
		
		if ($fmt =~ /\?/) { # Discover justification
			# Numbers justify right, strings left
			my ($tot, $num) = (0, 0);
			for my $item (@{$cols[$i]}) {
				$tot += length($item);
				$item =~ s/\D//g;
				$num += length($item);
			}
			my $just = ($num > $tot / 2) ? '' : '-';
			$fmt =~ s/\?/$just/;
		}
		
		$fmts->[$i] = $fmt;
	}
}

# columns($fmt, \@list, $colGen, %opts);
#
# Print something in columns.
# Opts include:
#	rank:	field to rank by
#	total:	last field is a total
sub columns {
	my ($fmt, $list, $colGen, %opts) = @_;
	unless (@$list) {
		print "No items found\n";
		return;
	}
	
	# Get the column contents
	my @data = map { {
		cols => [ $colGen->($_) ],
		($opts{rank} ? (rank => $opts{rank}->($_)) : ()),
	} } @$list;
	@data = sort { $b->{rank} <=> $a->{rank} } @data if $opts{rank};
	
	# Examine the format
	
	my @fmts;
	$fmt =~ s/%([^%\w]*)(\w)/push @fmts, $1; "\%$#fmts$2"/ge;
	_columnFormats($fmt, \@fmts, \@data, %opts);
	$fmt =~ s/%(\d+)/"\%$fmts[$1]"/ge;
	
	# Print the data
	my $width = termWidth;
	for my $i (0..$#data) {
		my @cols = @{$data[$i]->{cols}};
		my $line = sprintf $fmt, @cols;
		$width = length($line);
		
		print '-' x $width, "\n" if $i == $#data && $opts{total};
		printf "$line\n";
	}
}

# wrap($text, $first, $rest);
# 
# Wrap a line of text.
sub wrap {
	my ($text, $first, $rest) = @_;
	$first = '' unless defined $first;
	$rest = '' unless defined $rest;
	local $Text::Wrap::columns = termWidth;
	return Text::Wrap::wrap($first, $rest, $text);
}

# prettyPrint($text);
#
# Print some text nicely
sub prettyPrint {
	my ($text) = @_;
	print wrap($text);
}

1;