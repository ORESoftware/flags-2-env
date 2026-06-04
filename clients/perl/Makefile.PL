use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME => 'Flags2Env',
  VERSION_FROM => 'lib/Flags2Env.pm',
  ABSTRACT => 'Perl bindings for flags2env',
  AUTHOR => 'ORESoftware',
  LICENSE => 'mit',
  PREREQ_PM => {
    'FFI::Platypus' => '2.00',
    'JSON::PP' => '0',
  },
  META_MERGE => {
    resources => {
      repository => 'https://github.com/ORESoftware/flags-2-env',
      bugtracker => 'https://github.com/ORESoftware/flags-2-env/issues',
    },
  },
);
