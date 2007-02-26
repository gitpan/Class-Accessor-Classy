package Class::Accessor::Classy;
$VERSION = eval{require version}?version::qv($_):$_ for(0.1.2);

use warnings;
use strict;
use Carp;

=head1 NAME

Class::Accessor::Classy - accessors with minimal inheritance

=head1 SYNOPSIS

  package YourPackage;

  use Class::Accessor::Classy;
    with qw(new);              # with a new() method
    ro qw(foo);                # read-only
    rw qw(bar);                # read-write
    rs baz => \ (my $set_baz); # read-only, plus a secret writer

    # alternatively:
    my $set_bip = rs 'bip';

    ro_c suitcase => 'red';    # read-only class data
    rw_c hat      => 'black';  # read-write class data
    rs_c socks    => \ (my $set_socks) => undef;

    # alternative secret writer syntax
    my $set_shoes = rs_c shoes => undef;

    # also class read-only:
    constant seven => 7;
    constant eight => this->seven + 1;
  no  Class::Accessor::Classy;
  # ^-- removes all of the syntax bits from your namespace

  package whatever;

  YourPackage->set_hat(undef);
  my $obj = YourPackage->new(foo => 4, bar => 2);
  # NOTE I'm thinking of deprecating the get_foo() usage
  warn "foo ", $obj->foo;
  YourPackage->$set_socks("tube");

=head1 Frontend

Unlike other class-modifying code, this is not designed to be inherited
from.  Instead, you simply use it and get an invisible subclass
containing your accessors.  If you use the 'no' syntax (to call
unimport), you are left with a squeaky-clean namespace.

=cut

=head1 Utilities

This introspection stuff is unreliable -- don't use it.

=head2 find_accessors

  @attribs = Class::Accessor::Classy->find_accessors($class);

=cut

sub find_accessors {
  my $package = shift;
  my ($class) = @_;

  # TODO just cache them rather than introspect?

  my @classes = $package->find_subclasses($class);
  my @acc;
  foreach my $c (@classes) {
    no strict 'refs';
    push(@acc, keys(%{$c . '::'}));
  }
  my %skip = map({$_ => 1} qw(new import)); # XXX no introspecting!?
  my %got;
  return(
    grep({
      ($_ !~ m/^[gs]et_/) and (lc($_) ne 'isa') and
      ($got{$_} ? 0 : ($got{$_} = 1)) and
      (! $skip{$_})
    } @acc)
  );
} # end subroutine find_accessors definition
########################################################################

=head2 find_subclasses

  @classlist = Class::Accessor::Classy->find_subclasses($class);

=cut

sub find_subclasses {
  my $package = shift;
  my ($class) = @_;

  my $get_isa;
  $get_isa = sub {
    my ($p) = @_;
    my @isa = eval {no strict 'refs'; @{$p . '::ISA'}};
    $@ and die;
    return($p, map({$get_isa->($_)} @isa));
  };
  return(grep({$_ =~ m/::--accessors$/} $get_isa->($class)));
} # end subroutine find_subclasses definition
########################################################################

=head1 Subclassable

Customized subclasses may override these methods to create a new kind of
accessor generator.

=over

=item notation:

Read these as: $CAC = 'Class::Accessor::Classy'; (or whatever subclass
you're creating.)

=back

=head2 exports

  my %exports = $CAC->exports;

=cut

sub exports {
  my $package = shift; # allows us to be subclassed :-)
  my $CP = sub {$package->create_package(class => $_[0])};
  my %exports = (
    with => sub (@) {
      $package->make_standards($CP->(caller), @_);
    },
    this => sub () {
      (caller)[0];
    },
    constant => sub ($$) { # same as class_ro
      $package->make_class_data('ro', $CP->(caller), @_);
    },
    ro_c => sub {
      $package->make_class_data('ro', $CP->(caller), @_);
    },
    rw_c => sub {
      $package->make_class_data('rw', $CP->(caller), @_);
    },
    rs_c => sub {
      my @list = @_;
      my @pairs;
      my @refs;
      if((ref($list[1]) || '') eq 'SCALAR') {
        croak("number of elements in argument list") if(@list % 3);
        @pairs = map({[$list[$_*3], $list[$_*3+2]]} 0..($#list / 3));
        @refs =  map({$list[$_*3+1]} 0..($#list / 3));
      }
      else {
        @pairs = map({[$list[$_*2], $list[$_*2+1]]} 0..($#list / 2));
      }
      my @names;
      my $class = $CP->(caller);
      foreach my $pair (@pairs) {
        push(@names,
          $package->make_class_data('rs', $class, @$pair)
        );
      }
      if(@refs) {
        ${$refs[$_]} = $names[$_] for(0..$#names);
      }
      else {
        @names == @pairs or die "oops";
      }
      (@names > 1) or return($names[0]);
      return(@names);
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
      my $class = $CP->(caller);
      $package->make_getters($class, @list);
      $package->make_aliases($class, @list);
    },
    rw => sub (@) {
      my (@list) = @_;
      my $class = $CP->(caller);
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
      my $class = $CP->(caller);
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
    lo => sub {
      my (@list) = @_;
      my $class = $CP->(caller);
      foreach my $item (@list) {
        $package->make_array_method(
          class => $class,
          item  => $item, 
          functions => [qw(get)],
        );
      }
    },
    lw => sub { # no list here
      my ($item, @args) = @_;
      my @f = @args;
      @f and croak("not yet");
      $package->make_array_method(
        class => $CP->(caller),
        item  => $item, 
        functions => [qw(get set add), @f],
      );
    },
    ls => sub {
      my ($item, @args) = @_;
      my $setref = shift(@args) if((ref($args[0])||'') eq 'SCALAR');

      my @f;
      my @r;
      if((ref($args[1]) || '') eq 'SCALAR') {
        croak("odd number of elements in argument list") if(@args % 2);
        @f = map({$args[$_*2]} 0..($#args / 2));
        @r = map({$args[$_*2+1]} 0..($#args / 2));
      }
      else {
        @f = @args;
      }
      my @ans = $package->make_array_method(
        class => $CP->(caller),
        item  => $item, 
        functions => [qw(get set), @f],
        secret => 1,
      );

      $$setref = shift(@ans) if($setref);
      if(@r) {
        ${$r[$_]} = $ans[$_] for(0..$#ans);
      }
      return(@ans);
    },
  );
} # end subroutine exports definition
########################################################################

=head2 import

  $CAC->import;

=cut

sub import {
  my $package = shift;

  my $caller = caller();
  # we should never export to main
  croak 'cannot have accessors on the main package' if($caller eq 'main');
  my %exports = $package->exports;
  foreach my $name (keys(%exports)) {
    no strict 'refs';
    #no warnings 'redefine';
    #my $ugh = *{$caller . '::' . $name} if defined(&{$caller . '::' . $name});
    #warn "ugh $name ", $ugh if($ugh);
    *{$caller . '::' . $name} = $exports{$name};
  }
} # end subroutine import definition
########################################################################

=head2 unimport

  $CAC->unimport;

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

  my $package = $CAC->create_package(
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

=head2 install_sub

  $CAC->install_sub($class, $name, $subref, $note);

=cut

sub install_sub {
  my $package = shift;
  my ($class, $name, $subref, $note) = @_;
  my $fullname = $class . '::' . $name;
  {
    no strict 'refs';
    defined(&{$fullname}) and die;
    *{$fullname} = $subref;
  }
  $package->annotate($class, $name, $note) if($note);
  return($fullname);
} # end subroutine install_sub definition
########################################################################

=head2 annotate

  $CAC->annotate($class, $name, $note);

=cut

{
my %notes;
sub annotate {
  my $package = shift;
  my ($class, $name, $note) = @_;
  $notes{$class} ||= {};
  $notes{$class}{$name} = $note;
} # end subroutine annotate definition
########################################################################

=head2 get_notes

  my %notes = $CAC->get_notes;

=cut

sub get_notes {
  my $package = shift;
  return(%notes);
} # end subroutine get_notes definition
} # and closure
########################################################################

=head2 make_standards

  $CAC->make_standards($class, @list);

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
    $package->install_sub($class, $item, $subref, 'stock');
  }
} # end subroutine make_standards definition
} # end closure
########################################################################

=head2 make_getters

  $CAC->make_getters($class, @list);

=cut

sub make_getters {
  my $package = shift;
  my ($class, @list) = @_;
  foreach my $item (@list) {
    my $subref = $package->do_eval("sub {\$_[0]->{'$item'}}", $item);
    $package->install_sub($class, $item, $subref, 'getter');
  }
} # end subroutine make_getters definition
########################################################################

=head2 make_setters

  $CAC->make_setters($class, @list);

=cut

sub make_setters {
  my $package = shift;
  my ($class, @list) = @_;
  foreach my $item (@list) {
    my $subref = $package->do_eval(
      "sub {\$_[0]->{'$item'} = \$_[1]}", $item);
    $package->install_sub($class, 'set_' . $item, $subref, 'setter');
  }
} # end subroutine make_setters definition
########################################################################

=head2 make_secrets

  my @names = $CAC->make_secrets($class, @list);

=cut

sub make_secrets {
  my $package = shift;
  my ($class, @list) = @_;
  my @names;
  foreach my $item (@list) {
    my $subref = $package->do_eval(
      "sub {\$_[0]->{'$item'} = \$_[1]}", $item);
    my $name = '--set_' . $item;
    push(@names, $name);
    $package->install_sub($class, $name, $subref, 'private');
  }
  return(@names);
} # end subroutine make_secrets definition
########################################################################

=head2 make_aliases

  $CAC->make_aliases($class, @list);

=cut

sub make_aliases {
  my $package = shift;
  my ($class, @list) = @_;
  foreach my $item (@list) {
    my $subref = $package->do_eval("sub {\$_[0]->$item}", $item);
    $package->install_sub($class, 'get_' . $item, $subref, "->$item");
  }
} # end subroutine make_aliases definition
########################################################################

=head2 do_eval

  my $subref = $package->do_eval($string, @checks);

=cut

sub do_eval {
  my $self = shift;
  my ($string, @checks) = @_;
  foreach my $check (@checks) {
    ($check =~ m/^[a-z_][\w]*$/i) or croak("'$check' not a valid name");
  }
  my $subref = eval($string);
  $@ and croak("oops $@");
  return($subref);
} # end subroutine do_eval definition
########################################################################

=head1 List Accessors

=head2 make_array_method

  $CAC->make_array_method(
    class     => $class,
    item      => $name,
    functions => [@functions],
    secret    => $bool,
  );

If secret is true, will return the list of names.

=cut

sub make_array_method {
  my $package = shift;
  my %opts = @_;
  my $class = $opts{class} or die;
  my $item = $opts{item};
  my @functions = @{$opts{functions}};
  my %subs = $package->_get_array_subs($item);
  my @ret;
  ($item =~ m/^[a-z_][\w]*$/i) or croak("'$item' not a valid name");
  foreach my $f (@functions) {
    my $str = $subs{$f} or croak("no such function $f");
    my $name = $item;
    unless($f eq 'get') {
      $name = ($opts{secret} ? '--' : '') . $f . '_' . $item;
      $opts{secret} and push(@ret, $name);
    }
    my $subref = eval($str);
    $@ and croak("oops $@");
    $package->install_sub($class, $name, $subref,
      ($opts{secret} ? 'private ' : '') .  "$f array");
  }
  return(@ret);
} # end subroutine make_array_method definition
########################################################################

=head2 _get_array_subs

  my %subs = $CAC->_get_array_subs($name);

=cut

sub _get_array_subs {
  my $package = shift;
  my ($item) = @_;

  my $s = '$_[0]';
  my %subs = (
    get   => "sub {$s\->{$item} or return; \@{$s\->{$item}}}",
    set   => "sub {my \$self = shift;
      \$self->{$item} ||= []; \@{\$self->{$item}} = (\@_)}",
    inner => "sub {$s\->{$item}}",
    add   => "sub {my \$self = shift;
      \$self->{$item} or Carp::croak(\"'$item' list is empty\");
      push(\@{\$self->{$item}}, \@_);}",
    'pop' => "sub {$s\->{$item} or
      Carp::croak(\"'$item' list is empty\");
      pop(\@{\$self->{$item}});}",
    'shift' => "sub {$s\->{$item} or
      Carp::croak(\"'$item' list is empty\");
      shift(\@{\$self->{$item}});}",
    'unshift' => "sub {my \$self = shift;
      \$self->{$item} or Carp::croak(\"'$item' list is empty\");
      unshift(\@{\$self->{$item}}, \@_);}",
  );
  return(%subs);
} # end subroutine _get_array_subs definition
########################################################################

=head1 Class Accessors

=head2 make_class_data

  $CAC->make_class_data($mode, $class, $key, $value);

If mode is 'rs', returns the secret setter name.

=cut

sub make_class_data {
  my $package = shift;
  my ($mode, $class, $key, $value) = @_;

  my $getsub = sub {
    my $self = shift;
    return($value);
  };
  my $setsub = sub { # TODO should be like C.D.Inheritable?
    my $self = shift;
    $value = shift;
  };
  $package->install_sub($class, $key, $getsub, 'class getter');
  if($mode eq 'rw') {
    $package->install_sub($class, 'set_' . $key, $setsub,
      'class setter');
  }
  elsif($mode eq 'rs') {
    my $name = '--set_' . $key;
    $package->install_sub($class, $name, $setsub,
      'private class setter');
    return($name);
  }
  else {
    ($mode eq 'ro') or die "no such mode '$mode'";
  }
  return;
} # end subroutine make_class_data definition
########################################################################

# TODO 
# opt '+aliases';
# opts prefix => '_';
# $package->options

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

Copyright (C) 2006-2007 Eric L. Wilhelm, All Rights Reserved.

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
