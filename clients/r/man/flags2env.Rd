\name{flags2env}
\alias{parse_flags}
\alias{parse_process}
\alias{apply_flags}
\title{Parse flags2env command-line values}
\description{
Parse command-line arguments with the flags2env native parser and optionally
merge the resulting string values into an existing environment map.
}
\usage{
parse_flags(argv = commandArgs(FALSE), config_path = NULL)

parse_process(config_path = NULL)

apply_flags(
  env = Sys.getenv(),
  argv = commandArgs(FALSE),
  config_path = NULL
)
}
\arguments{
  \item{argv}{A character vector containing the program name and arguments.}
  \item{config_path}{An optional path to a \file{.cli-flags.toml} file.}
  \item{env}{A named character vector to receive parsed overrides.}
}
\value{
\code{parse_flags()} and \code{parse_process()} return a named character
vector. \code{apply_flags()} returns \code{env} with parsed values applied.
}
