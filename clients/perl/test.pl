use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Flags2Env;

$ENV{FLAGS2ENV_NATIVE_LIB} ||= "$FindBin::Bin/../../build/libflags2env.so";

my $flags = Flags2Env->new();
my $config = "$FindBin::Bin/../../tests/fixtures/.cli-flags.toml";
my $parsed = $flags->parse([qw(app --debug=t --port 8181)], $config);
die "unexpected parsed map" unless $parsed->{DEBUG} eq "true" && $parsed->{PORT} eq "8181";

my $combined = $flags->apply({ PORT => "env", KEEP => "1" }, [qw(app --port 8181)], $config);
die "unexpected combined map" unless $combined->{PORT} eq "8181" && $combined->{KEEP} eq "1";
