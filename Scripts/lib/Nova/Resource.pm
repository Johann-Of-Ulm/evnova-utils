﻿# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(collection readOnly));

use Nova::Util qw(deaccent);

use Scalar::Util qw(blessed);
use Storable;
use Carp;

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

# Register a package to handle some type
sub register {
	my ($pkg, $type) = @_;
	$REGISTERED{deaccent($type)} = $pkg;
}

# Textual representation of the given fields of this resource (or all fields,
# if none are specified).
sub dump {
	my ($self, @fields) = @_;
	@fields = $self->fieldNames unless @fields;
	
	my $dump = '';
	for my $field (@fields) {
		$dump .= sprintf "%s: %s\n", $field, $self->_raw_field($field)->dump;
	}
	return $dump;
}

# Get/set the raw Resource::Value of a field
sub _raw_field {
	my ($self, $field, $val) = @_;
	my $lc = lc $field;
	
	# Gotta be careful, with the damn hash pointer
	die "No such field '$field'\n" unless $self->hasField($field);
	if (defined $val) {
		die "Read-only!\n" if $self->readOnly;
		
		my $valobj = ${$self->{fields}}->{$lc};
		if (eval { $val->isa('Nova::Resource::Value') }) {
			$valobj = $val;
		} else {
			$valobj = $valobj->new($val);	# keep the same type
		}
		
		# update so that MLDBM notices
		my %fields = %${$self->{fields}};
		$fields{$lc} = $valobj;
		${$self->{fields}} = { %fields };
	}
	return ${$self->{fields}}->{$lc};
}

# Do we have the given field?
sub hasField {
	my ($self, $field) = @_;
	return exists ${$self->{fields}}->{lc $field};
}

# Eliminate warning on DESTROY
sub DESTROY { }

# $self->_caseInsensitiveMethod($subname);
#
# Find a method in the inheritance tree which equals the given name when
# case is ignored.
sub _caseInsensitiveMethod {
	my ($pkg, $sub) = @_;
	
	# Save the methods for each package we look at
	my $subs = $pkg->symref('_CASE_INSENSITIVE_SUBS');
	unless (defined $$subs) {
		my %methods = $pkg->methods;
		$$subs->{lc $_} = $methods{$_} for keys %methods;
	}
	if (exists $$subs->{lc $sub}) {
		return $$subs->{lc $sub};
	}
	
	# Try going up in the inheritance tree
	for my $base (@{$pkg->symref('ISA')}) {
		if ($base->can('_caseInsensitiveMethod')) {
			return $base->_caseInsensitiveMethod($sub);
		}
	}
	return undef;
}

sub can {
	my ($self, $meth) = @_;
	my $code = $self->_caseInsensitiveMethod($meth);
	return $code if defined $code;
	
	# Can't test for field presence without a blessed object!
	return undef unless blessed $self;
	return undef unless $self->hasField($meth);
	return sub {
		my ($self, @args) = @_;
		$self->_raw_field($meth, @args)->value;
	};
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	my $fullsub = our $AUTOLOAD;
	my ($pkg, $sub) = ($fullsub =~ /(.*)::(.*)/);
	my $code = $self->can($sub);
	die "No such method '$sub'\n" unless defined $code;
	goto &$code;
	
	# We can't use the insert-and-goto trick, since it interferes with
	# overriding methods.
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

# Wrapper for methods using precalculation optimization
sub precalc {
	my ($self, $name, $code) = @_;
	return $self->collection->store($name) if $self->collection->store($name);
	
	my $file = Nova::Cache->storableCache($self->source, $name);
	my $cache = eval { retrieve $file };
	unless (defined $cache) {
		$cache = { };
		$code->($self, $cache);
		store $cache, $file;
	}
	return $self->collection->store($name => $cache);
}

# Get the default values for a field. Returned as a hash-ref, where keys
# exist for only the defaults values.
sub fieldDefault {
	my ($self, $field) = @_;	
	
	my $defaults = $self->symref('_DEFAULT_FIELDS');
	unless (defined $$defaults) {
		my %hash = $self->fieldDefaults;
		while (my ($k, $v) = each %hash) {
			my @d = ref($v) ? @$v : ($v);
			$$defaults->{lc $k}{$_} = $1 for @d;
		}
	}
	
	return { '' => 1 } unless exists $$defaults->{lc $field};
	return $$defaults->{lc $field}
}

# Get the defaults for all relevant fields
sub fieldDefaults {
	my ($self) = @_;
	return ();
	# Override in subclasses
}

# Return the value of a field, or undef if it's the default value
sub fieldDefined {
	my ($self, $field) = @_;
	my $defaults = $self->fieldDefault($field);
	my $val = $self->$field;
	return undef if exists $defaults->{$val};
	return $val;
}

# Create a clone of this resource, at a different ID
sub duplicate {
	my ($self, $id) = @_;
	$id = $self->collection->nextUnused($self->type) unless defined $id;
	
	my $fields = $self->fieldHash;
	$fields->{id} = $id;
	$self->collection->addResource($fields);
}

# Load the categories
package Nova::Resource::Category;
use base qw(Nova::Base);
__PACKAGE__->subPackages;

# Load the types
package Nova::Resource::Type;
use base qw(Nova::Base);
__PACKAGE__->subPackages;


1;
