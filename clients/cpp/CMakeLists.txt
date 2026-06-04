cmake_minimum_required(VERSION 3.16)
project(flags2env_cpp VERSION 0.1.0 LANGUAGES C CXX)

add_library(flags2env_native STATIC ../../src/parser.c)
target_include_directories(flags2env_native PUBLIC ../../src)
set_target_properties(flags2env_native PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(flags2env_cpp INTERFACE)
target_include_directories(flags2env_cpp INTERFACE include ../../src)
target_link_libraries(flags2env_cpp INTERFACE flags2env_native)
