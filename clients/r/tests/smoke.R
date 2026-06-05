config <- tempfile(fileext = ".toml")
on.exit(unlink(config), add = TRUE)
writeLines(c(
  "[flags.port]",
  "env = \"PORT\"",
  "aliases = [\"port\"]",
  "type = \"integer\"",
  "",
  "[flags.debug]",
  "env = \"DEBUG\"",
  "aliases = [\"debug\"]",
  "type = \"bool\"",
  "true_aliases = [\"t\"]"
), config)

parsed <- flags2env::parse_flags(c("app", "--debug=t", "--port", "8181"), config)
stopifnot(identical(parsed[["DEBUG"]], "true"))
stopifnot(identical(parsed[["PORT"]], "8181"))

combined <- flags2env::apply_flags(c(PORT = "env", KEEP = "1"), c("app", "--port", "8181"), config)
stopifnot(identical(combined[["PORT"]], "8181"))
stopifnot(identical(combined[["KEEP"]], "1"))
