as_string_map <- function(raw) {
  parsed <- jsonlite::fromJSON(raw %||% "{}", simplifyVector = TRUE)
  if (length(parsed) == 0) {
    return(stats::setNames(character(), character()))
  }
  stats::setNames(as.character(parsed), names(parsed))
}

parse_flags <- function(argv = commandArgs(FALSE), config_path = NULL) {
  as_string_map(.Call("f2e_r_parse", as.character(argv), config_path %||% NA_character_))
}

parse_process <- function(config_path = NULL) {
  as_string_map(.Call("f2e_r_parse_process", config_path %||% NA_character_))
}

apply_flags <- function(env = Sys.getenv(), argv = commandArgs(FALSE), config_path = NULL) {
  parsed <- parse_flags(argv, config_path)
  env[names(parsed)] <- parsed
  env
}

`%||%` <- function(left, right) {
  if (is.null(left)) right else left
}
