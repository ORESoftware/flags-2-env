# Flags2Env Fortran

Fortran bindings for the `flags2env` native parser.

The fpm package includes `src/flags2env.f90` plus package-local `parser.c` and
`parser.h` sources, so consumers can build the native parser alongside the
Fortran module without relying on the monorepo root.
