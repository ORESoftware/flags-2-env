program test_flags2env
  use flags2env
  implicit none

  character(len=:), allocatable :: parsed

  parsed = parse_json_argv_from_file('tests/fixtures/.cli-flags.toml', '["app","--port","8181","--debug=t"]')
  if (index(parsed, '"PORT":"8181"') == 0) error stop "missing PORT"
  if (index(parsed, '"DEBUG":"true"') == 0) error stop "missing DEBUG"
end program
