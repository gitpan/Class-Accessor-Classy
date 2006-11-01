use Test::More tests => 3;

eval("use Class::Accessor::Classy ();");
ok(! $@, 'use_ok') or BAIL_OUT("load failed: $@");
eval("use Class::Accessor::Classy;");
ok($@);
like($@, qr/^cannot have accessors on the main package/);

diag( "Testing Class::Accessor::Classy ", Class::Accessor::Classy->VERSION );

# vi:syntax=perl:ts=2:sw=2:et:sta
