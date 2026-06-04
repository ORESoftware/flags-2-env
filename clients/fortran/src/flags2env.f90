module flags2env
  use, intrinsic :: iso_c_binding
  implicit none

  interface
    function c_parse_json_argv(argv_json) bind(C, name="f2e_parse_json_argv") result(ptr)
      import :: c_char, c_ptr
      character(kind=c_char), dimension(*) :: argv_json
      type(c_ptr) :: ptr
    end function

    function c_parse_json_argv_from_file(config_path, argv_json) bind(C, name="f2e_parse_json_argv_from_file") result(ptr)
      import :: c_char, c_ptr
      character(kind=c_char), dimension(*) :: config_path
      character(kind=c_char), dimension(*) :: argv_json
      type(c_ptr) :: ptr
    end function

    function c_parse_process() bind(C, name="f2e_parse_process") result(ptr)
      import :: c_ptr
      type(c_ptr) :: ptr
    end function

    function c_parse_process_from_file(config_path) bind(C, name="f2e_parse_process_from_file") result(ptr)
      import :: c_char, c_ptr
      character(kind=c_char), dimension(*) :: config_path
      type(c_ptr) :: ptr
    end function

    subroutine c_f2e_free(value) bind(C, name="f2e_free")
      import :: c_ptr
      type(c_ptr), value :: value
    end subroutine

    function c_strlen(value) bind(C, name="strlen") result(length)
      import :: c_ptr, c_size_t
      type(c_ptr), value :: value
      integer(c_size_t) :: length
    end function
  end interface

contains
  function parse_json_argv(argv_json) result(json)
    character(len=*), intent(in) :: argv_json
    character(len=:), allocatable :: json
    character(kind=c_char), allocatable, target :: c_argv(:)

    c_argv = to_c_string(argv_json)
    json = owned_string(c_parse_json_argv(c_argv))
  end function

  function parse_json_argv_from_file(config_path, argv_json) result(json)
    character(len=*), intent(in) :: config_path
    character(len=*), intent(in) :: argv_json
    character(len=:), allocatable :: json
    character(kind=c_char), allocatable, target :: c_config(:)
    character(kind=c_char), allocatable, target :: c_argv(:)

    c_config = to_c_string(config_path)
    c_argv = to_c_string(argv_json)
    json = owned_string(c_parse_json_argv_from_file(c_config, c_argv))
  end function

  function parse_process() result(json)
    character(len=:), allocatable :: json
    json = owned_string(c_parse_process())
  end function

  function parse_process_from_file(config_path) result(json)
    character(len=*), intent(in) :: config_path
    character(len=:), allocatable :: json
    character(kind=c_char), allocatable, target :: c_config(:)

    c_config = to_c_string(config_path)
    json = owned_string(c_parse_process_from_file(c_config))
  end function

  function to_c_string(value) result(out)
    character(len=*), intent(in) :: value
    character(kind=c_char), allocatable :: out(:)
    integer :: i

    allocate(out(len(value) + 1))
    do i = 1, len(value)
      out(i) = value(i:i)
    end do
    out(len(value) + 1) = c_null_char
  end function

  function owned_string(ptr) result(value)
    type(c_ptr), intent(in) :: ptr
    character(len=:), allocatable :: value
    character(kind=c_char), pointer :: chars(:)
    integer(c_size_t) :: n
    integer :: i
    integer :: length

    if (.not. c_associated(ptr)) then
      value = "{}"
      return
    end if

    n = c_strlen(ptr)
    length = int(n)
    call c_f_pointer(ptr, chars, [length])
    allocate(character(len=length) :: value)
    do i = 1, length
      value(i:i) = chars(i)
    end do
    call c_f2e_free(ptr)
  end function
end module
