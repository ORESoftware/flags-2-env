#include "parser.h"

#include <R_ext/Rdynload.h>
#include <Rinternals.h>
#include <stdlib.h>

static SEXP f2e_r_owned_string(char *value) {
  SEXP out = PROTECT(Rf_mkString(value ? value : "{}"));
  if (value) {
    f2e_free(value);
  }
  UNPROTECT(1);
  return out;
}

SEXP f2e_r_parse(SEXP argv, SEXP config_path) {
  R_xlen_t argc = XLENGTH(argv);
  const char **items = NULL;
  if (argc > 0) {
    items = (const char **)calloc((size_t)argc, sizeof(char *));
    if (!items) {
      return Rf_mkString("{}");
    }
  }

  for (R_xlen_t i = 0; i < argc; i++) {
    items[i] = CHAR(STRING_ELT(argv, i));
  }

  const char *config = NULL;
  if (!Rf_isNull(config_path) && TYPEOF(config_path) == STRSXP && XLENGTH(config_path) > 0 && STRING_ELT(config_path, 0) != NA_STRING) {
    config = CHAR(STRING_ELT(config_path, 0));
  }

  char *json = config ? f2e_parse_from_file(config, (int)argc, items) : f2e_parse((int)argc, items);
  free(items);
  return f2e_r_owned_string(json);
}

SEXP f2e_r_parse_process(SEXP config_path) {
  const char *config = NULL;
  if (!Rf_isNull(config_path) && TYPEOF(config_path) == STRSXP && XLENGTH(config_path) > 0 && STRING_ELT(config_path, 0) != NA_STRING) {
    config = CHAR(STRING_ELT(config_path, 0));
  }
  return f2e_r_owned_string(config ? f2e_parse_process_from_file(config) : f2e_parse_process());
}

static const R_CallMethodDef call_methods[] = {
  {"f2e_r_parse", (DL_FUNC)&f2e_r_parse, 2},
  {"f2e_r_parse_process", (DL_FUNC)&f2e_r_parse_process, 1},
  {NULL, NULL, 0}
};

void R_init_flags2env(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
