cmake_minimum_required(VERSION 3.16)
project(flags2env_cpp VERSION 0.1.0 LANGUAGES C CXX)

add_library(flags2env_native STATIC native/parser.c)
target_include_directories(flags2env_native PUBLIC native)
set_target_properties(flags2env_native PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(flags2env_cpp INTERFACE)
target_include_directories(flags2env_cpp INTERFACE include native)
target_link_libraries(flags2env_cpp INTERFACE flags2env_native)

include(CTest)
if(BUILD_TESTING)
  add_executable(flags2env_cpp_smoke test.cpp)
  target_link_libraries(flags2env_cpp_smoke PRIVATE flags2env_cpp)
  add_test(NAME flags2env_cpp_smoke COMMAND flags2env_cpp_smoke)
endif()
