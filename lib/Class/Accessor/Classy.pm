package Class::Accessor::Classy;
$VERSION = eval{require version}?version::qv($_):$_ for(0.1.1);

use warnings;
use strict;
use Carp;

=head1 NAME

Class::Accessor::Classy - accessors with minimal inheritance

=head1 SYNOPSIS

  use Class::Accessor::Classy;
    with qw(new);             # with a new() method
    ro qw(foo);               # read-only
    rw qw(bar);               # read-write
    rs baz => \(my $set_baz); # read-only, plus a secret writer
  no  Class::Accessor::Classy;

=cut


=head2 exports

  my %exports = Class::Accessor::Classy->exports;

=cut

sub exports {
  my $package = shift; # allows us to be subclassed :-)
  my %exports = (
    with => sub (@) {
      my (@list) = @_;
      my $caller = caller;
      my $class = $package->create_package(class => $caller);
      $package->make_standards($class, @list);
    },
    in => sub ($) {
      # put them in this package
      my ($in) = @_;
      my $caller = caller;
      my $class = $package->create_package(
        class => $caller,
        in    => $in,
      );
    },
    ro => sub (@) {
      my (@list) = @_;
      my $caller = caller;
      my $class = $package->create_package(class => $caller);
      $package->make_getters($class, @list);
      $package->make_aliases($class, @list);
    },
    rw => sub (@) {
      my (@list) = @_;
      my $caller = caller;
      my $class = $package->create_package(class => $caller);
      $package->make_getters($class, @list);
      $package->make_aliases($class, @list);
      $package->make_setters($class, @list);
    },
    rs => sub (@) {
      my (@list) = @_;
      # decide if we got passed refs or should return a list
      my @items;
      my @refs;
      if((ref($list[1]) || '') eq 'SCALAR') {
        croak("odd number of elements in argument list") if(@list % 2);
        @items = map({$list[$_*2]} 0..($#list / 2));
        @refs =  map({$list[$_*2+1]} 0..($#list / 2));
      }
      else {
        @items = @list;
      }
      my $caller = caller;
      my $class = $package->create_package(class => $caller);
      $package->make_getters($class, @items);
      $package->make_aliases($class, @items);
      my @names = $package->make_secrets($class, @items);
      (@names == @items) or die "oops";
      if(@refs) {
        ${$refs[$_]} = $names[$_] for(0..$#names);
      }
      (@names > 1) or return($names[0]);
      return(@names);
    },
  );
} # end subroutine exports definition
########################################################################

=head2 import

  Class::Accessor::Classy->import;

=cut

sub import {
  my $package = shift;

  my $caller = caller();
  # we should never export to main
  croak 'cannot have accessors on the main package' if($caller eq 'main');
  my %exports = $package->exports;
  foreach my $name (keys(%exports)) {
    no strict 'refs';
    *{$caller . '::' . $name} = $exports{$name};
  }
} # end subroutine import definition
########################################################################

=head2 unimport

  Class::Accessor::Classy->unimport;

=cut

sub unimport {
  my $package = shift;

  my $caller = caller();
  my %exports = $package->exports;
  #carp "unimport $caller";
  foreach my $name (keys(%exports)) {
    no strict 'refs';
    if(defined(&{$caller . '::' . $name})) {
      delete(${$caller . '::'}{$name});
    }
  }
} # end subroutine unimport definition
########################################################################



=head2 create_package

Creates and returns the package in which the accessors will live.  Also
pushes the created accessor package into the caller's @ISA.

If it already exists, simply returns the cached value.

  my $package = Class::Accessor::Classy->create_package(
    class => $caller,
    in    => $package, # optional
  );

=cut

{
my %package_map;
sub create_package {
  my $this_package = shift;
  (@_ % 2) and croak("odd number of elements in argument list");
  my (%options) = @_;

  my $class = $options{class} or croak('no class?');
  if(exists($package_map{$class})) {
    # check for attempt to change package (not allowed)
    if(exists($options{in})) {
      ($package_map{$class} eq $options{in}) or die;
    }
    return($package_map{$class});
  }

  # use a package that can't be stepped on unless they ask for one
  my $package = $options{in} || $class . '::--accessors';
  $package_map{$class} = $package;

  my $class_isa = do { no strict 'refs'; \@{"${class}::ISA"}; };
  push(@$class_isa, $package)
    unless(grep({$_ eq $package} @$class_isa));
  return($package);
} # end subroutine create_package definition
} # and closure
########################################################################

=head2 make_standards

  Class::Accessor::Classy->make_standards($class, @list);

=cut

{
my %standards = (
  'new' => sub {
    my $class = shift;
    croak('odd number of elements in argument list') if(@_ % 2);
    my $self = {@_};
    bless($self, $class);
    return($self);
  }
);
sub make_standards {
  my $package = shift;
  my ($class, @list) = @_;
  @list or croak("no list?");
  foreach my $item (@list) {
    my $subref = $standards{$item} or
      croak("no standard method for '$item'");
    no strict 'refs';
    *{$class . '::' . $item} = $subref;
  }
} # end subroutine make_standards definition
} # end closure
########################################################################

=head2 make_getters

  Class::Accessor::Classy->make_getters($class, @list);

=cut

sub make_getters {
  my $package = shift;
  my ($class, @list) = @_;
  foreach my $item (@list) {
    ($item =~ m/^[a-z_][\w]*$/i) or croak("'$item' not a valid name");
    my $subref = eval("sub {\$_[0]->{'$item'}}");
    $@ and croak("oops $@");
    no strict 'refs';
    *{$class . '::' . $item} = $subref;
  }
} # end subroutine make_getters definition
########################################################################

=head2 make_setters

  Class::Accessor::Classy->make_setters($class, @list);

=cut

sub make_setters {
  my $package = shift;
  my ($class, @list) = @_;
  foreach my $item (@list) {
    ($item =~ m/^[a-z_][\w]*$/i) or croak("'$item' not a valid name");
    my $subref = eval("sub {\$_[0]->{'$item'} = \$_[1]}");
    $@ and croak("oops $@");
    no strict 'refs';
    *{$class . '::set_' . $item} = $subref;
  }
} # end subroutine make_setters definition
########################################################################

=head2 make_secrets

  my @names = Class::Accessor::Classy->make_secrets($class, @list);

=cut

sub make_secrets {
  my $package = shift;
  my ($class, @list) = @_;
  my @names;
  foreach my $item (@list) {
    ($item =~ m/^[a-z_][\w]*$/i) or croak("'$item' not a valid name");
    my $subref = eval("sub {\$_[0]->{'$item'} = \$_[1]}");
    $@ and croak("oops $@");
    my $name = '--set_' . $item;
    push(@names, $name);
    no strict 'refs';
    *{$class . '::' . $name} = $subref;
  }
  return(@names);
} # end subroutine make_secrets definition
########################################################################

=head2 make_aliases

  Class::Accessor::Classy->make_aliases($class, @list);

=cut

sub make_aliases {
  my $package = shift;
  my ($class, @list) = @_;
  foreach my $item (@list) {
    ($item =~ m/^[a-z_][\w]*$/i) or croak("'$item' not a valid name");
    my $subref = eval("sub {\$_[0]->$item}");
    $@ and croak("oops $@");
    no strict 'refs';
    *{$class . '::get_' . $item} = $subref;
  }
} # end subroutine make_aliases definition
########################################################################

=head1 AUTHOR

Eric Wilhelm @ <ewilhelm at cpan dot org>

http://scratchcomputing.com/

=head1 BUGS

If you found this module on CPAN, please report any bugs or feature
requests through the web interface at L<http://rt.cpan.org>.  I will be
notified, and then you'll automatically be notified of progress on your
bug as I make changes.

If you pulled this development version from my /svn/, please contact me
directly.

=head1 COPYRIGHT

Copyright (C) 2006 Eric L. Wilhelm, All Rights Reserved.

=head1 NO WARRANTY

Absolutely, positively NO WARRANTY, neither express or implied, is
offered with this software.  You use this software at your own risk.  In
case of loss, no person or entity owes you anything whatseover.  You
have been warned.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

# vi:ts=2:sw=2:et:sta
1;
