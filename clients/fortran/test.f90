program test_flags2env
  use flags2env
  implicit none

  character(len=:), allocatable :: parsed
  character(len=*), parameter :: config_path = 'flags2env-fortran-smoke.toml'

  open(unit=10, file=config_path, status='replace', action='write')
  write(10, '(A)') '[flags.port]'
  write(10, '(A)') 'env = "PORT"'
  write(10, '(A)') 'aliases = ["port"]'
  write(10, '(A)') 'type = "integer"'
  write(10, '(A)') ''
  write(10, '(A)') '[flags.debug]'
  write(10, '(A)') 'env = "DEBUG"'
  write(10, '(A)') 'aliases = ["debug"]'
  write(10, '(A)') 'type = "bool"'
  write(10, '(A)') 'true_aliases = ["t"]'
  close(10)

  parsed = parse_json_argv_from_file(config_path, '["app","--port","8181","--debug=t"]')
  open(unit=10, file=config_path, status='old', action='read')
  close(10, status='delete')

  if (index(parsed, '"PORT":"8181"') == 0) error stop "missing PORT"
  if (index(parsed, '"DEBUG":"true"') == 0) error stop "missing DEBUG"
end program
