﻿# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(collection readOnly));

use Nova::Util qw(deaccent);

=head1 NAME

Nova::Resource - a resource from a Nova data file

=head1 SYNOPSIS

  my $resource = Nova::Resource->new($fieldNames, \$fieldsHash, $collection);
  print $resource->dump;
  
  my $value = $resource->field("Flags");
  my $value = $resource->flags;

  # For subclasses
  Nova::Resource->register($package, @types);

=cut

our %REGISTERED;
__PACKAGE__->subPackages;

# my $resource = Nova::Resource->new(%params);
#
# fieldNames is an array ref of field names
# fields points to the cache entry
# collection is the Resources object, for referral to other resources
# readOnly is true if we should be read-only
sub init {
	my ($self, %params) = @_;
	$self->{fieldNames} = $params{fieldNames};
	$self->collection($params{collection});
	$self->{fields} = $params{fields};
	$self->readOnly($params{readOnly});
	
	# Rebless, if necessary
	my $t = deaccent($self->type);
	if (exists $REGISTERED{$t}) {
		bless $self, $REGISTERED{$t};
	}
	return $self;
}

# Register a package to handle some types
sub register {
	my ($pkg, @types) = @_;
	$REGISTERED{$_} = $pkg for @types;
}

# Textual representation of the given fields of this resource (or all fields,
# if none are specified).
sub show {
	my ($self, @fields) = @_;
	@fields = $self->fieldNames unless @fields;
	
	my $dump = '';
	for my $field (@fields) {
		$dump .= sprintf "%s: %s\n", $field, $self->_raw_field($field)->show;
	}
	return $dump;
}

# Get/set the raw Resource::Value of a field
sub _raw_field {
	my ($self, $field, $val) = @_;
	my $lc = lc $field;
	
	# Gotta be careful, with the damn hash pointer
	die "No such field '$field'\n" unless exists ${$self->{fields}}->{$lc};
	if (defined $val) {
		die "Read-only!\n" if $self->readOnly;
		
		my $valobj = ${$self->{fields}}->{$lc};
		$valobj = $valobj->new($val);	# keep the same type
		
		# update so that MLDBM notices
		my %fields = %${$self->{fields}};
		$fields{$lc} = $valobj;
		${$self->{fields}} = { %fields };
	}
	return ${$self->{fields}}->{$lc};
}

# Eliminate warning on DESTROY
sub DESTROY { }

# $self->_caseInsensitiveMethod($subname);
#
# Find a method in the inheritance tree which equals the given name when
# case is ignored.
sub _caseInsensitiveMethod {
	my ($pkg, $sub) = @_;
	$pkg = ref $pkg || $pkg;
	
	# Save the methods for each package we look at
	no strict 'refs';
	my $subs = \${"${pkg}::_SUBS"};
	unless (defined $$subs) {
		$$subs->{lc $_} = \&{"${pkg}::$_"} for $pkg->methods;
	}
	if (exists $$subs->{lc $sub}) {
		return $$subs->{lc $sub};
	}
	
	# Try going up in the inheritance tree
	for my $base (@{"${pkg}::ISA"}) {
		if ($base->can('_caseInsensitiveMethod')) {
			return $base->_caseInsensitiveMethod($sub);
		}
	}
	return undef;
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	my $fullsub = our $AUTOLOAD;
	my ($pkg, $sub) = ($fullsub =~ /(.*)::(.*)/);
	
	my $code = $self->_caseInsensitiveMethod($sub);
	if (defined $code) {
		# Try to call an existing sub with the same name (case-insensitive)
		$code->($self, @args);
	} else {
		# Otherwise, get the field with that name
		return $self->_raw_field($sub, @args)->value;
	}
}

# Get/set a field
sub field {
	my ($self, $field, $val) = @_;
	return defined $val ? $self->$field($val) : $self->$field;
}

# Get the field names
sub fieldNames {
	my ($self) = @_;
	return @{$self->{fieldNames}};
}

# Get a hash of field names to values. Used for dumping.
sub fieldHash {
	my ($self) = @_;
	return %${$self->{fields}};
}

# Get a full name, suitable for printing
sub fullName {
	my ($self) = @_;
	return $self->name;
}

# The source file for this resource and friends
sub source { $_[0]->collection->source }

# my @props = $r->multi($prefix);
#
# Get a list of properties with the same prefix
sub multi {
	my ($self, $prefix) = @_;
	my @k = grep /^$prefix/i, $self->fieldNames;
	return grep { $_ != -1 && $_ != -2 } map { $self->$_ } @k;
}

# my @objs = $r->multiObjs($primary, @secondaries);
#
# Get a list of object-like hashes
sub multiObjs {
	my ($self, $primary, @secondaries) = @_;
	my @k = grep /^$primary/i, $self->fieldNames;
	@k = grep { my $v = $self->$_; $v != -1 && $v != 0 } @k;
	
	my @ret;
	for my $k (@k) {
		my %h;
		for my $v ($primary, @secondaries) {
			(my $kv = $k) =~ s/^$primary/$v/;
			$h{$v} = $self->$kv;
		}
		push @ret, \%h;
	}
	return @ret;
}

1;
