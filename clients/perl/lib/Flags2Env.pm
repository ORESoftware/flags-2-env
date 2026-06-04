package Flags2Env;

use strict;
use warnings;
use FFI::Platypus 2.00;
use JSON::PP qw(encode_json decode_json);

our $VERSION = '0.1.0';

sub new {
  my ($class, %opts) = @_;
  my $lib = $opts{library_path} || $ENV{FLAGS2ENV_NATIVE_LIB} || _default_library_name();
  my $ffi = FFI::Platypus->new(api => 2);
  $ffi->lib($lib);

  my $free = $ffi->function(f2e_free => ['opaque'] => 'void');
  $ffi->custom_type(owned_string => {
    native_type => 'opaque',
    native_to_perl => sub {
      my ($ptr) = @_;
      return '{}' unless $ptr;
      my $raw = $ffi->cast('opaque' => 'string', $ptr);
      $free->call($ptr);
      return $raw;
    },
  });

  $ffi->attach(f2e_parse_json_argv => ['string'] => 'owned_string');
  $ffi->attach(f2e_parse_json_argv_from_file => ['string', 'string'] => 'owned_string');
  $ffi->attach(f2e_parse_process => [] => 'owned_string');
  $ffi->attach(f2e_parse_process_from_file => ['string'] => 'owned_string');

  return bless { ffi => $ffi }, $class;
}

sub parse {
  my ($self, $argv, $config_path) = @_;
  my $json = encode_json([map { "$_" } @{ $argv || [] }]);
  my $raw = defined $config_path
    ? f2e_parse_json_argv_from_file($config_path, $json)
    : f2e_parse_json_argv($json);
  return _string_map($raw);
}

sub parse_process {
  my ($self, $config_path) = @_;
  my $raw = defined $config_path
    ? f2e_parse_process_from_file($config_path)
    : f2e_parse_process();
  return _string_map($raw);
}

sub apply {
  my ($self, $env, $argv, $config_path) = @_;
  return { %{ $env || {} }, %{ $self->parse($argv, $config_path) } };
}

sub _string_map {
  my ($raw) = @_;
  my $decoded = decode_json($raw || '{}');
  return { map { $_ => "$decoded->{$_}" } keys %$decoded };
}

sub _default_library_name {
  return 'flags2env.dll' if $^O =~ /MSWin32|cygwin/;
  return 'libflags2env.dylib' if $^O eq 'darwin';
  return 'libflags2env.so';
}

1;
