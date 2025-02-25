cmake_minimum_required(VERSION 3.6)
project(client)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra")

include(FetchContent)

FetchContent_Declare(
    httplib
    URL https://github.com/yhirose/cpp-httplib/archive/refs/heads/master.zip
)

FetchContent_MakeAvailable(httplib)

# add_library(client STATIC main.cpp)
include_directories(${httplib_SOURCE_DIR})
add_executable(client client.cpp)

