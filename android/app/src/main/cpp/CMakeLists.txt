cmake_minimum_required(VERSION 3.22)

project(kazumi_rife LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT ANDROID_ABI STREQUAL "arm64-v8a")
  add_library(kazumi_rife SHARED kazumi_rife_stub.c)
  target_include_directories(kazumi_rife PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  return()
endif()

include(FetchContent)

# Keep the inference runtime reproducible. This is the ncnn revision used by
# the RIFE-NCNN implementation vendored in this directory.
set(NCNN_BUILD_BENCHMARK OFF CACHE BOOL "" FORCE)
set(NCNN_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(NCNN_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(NCNN_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(NCNN_DISABLE_EXCEPTION OFF CACHE BOOL "" FORCE)
set(NCNN_DISABLE_RTTI ON CACHE BOOL "" FORCE)
set(NCNN_INSTALL_SDK OFF CACHE BOOL "" FORCE)
set(NCNN_PIXEL_AFFINE OFF CACHE BOOL "" FORCE)
set(NCNN_PIXEL_DRAWING OFF CACHE BOOL "" FORCE)
set(NCNN_PIXEL_ROTATE OFF CACHE BOOL "" FORCE)
set(NCNN_VULKAN ON CACHE BOOL "" FORCE)
set(NCNN_VULKAN_ONLINE_SPIRV ON CACHE BOOL "" FORCE)

FetchContent_Declare(
  ncnn
  GIT_REPOSITORY https://github.com/Tencent/ncnn.git
  GIT_TAG 305837fd4a722ebc47c5d72e72d8ec9ae970e932
  GIT_PROGRESS TRUE
)
FetchContent_MakeAvailable(ncnn)

add_library(
  kazumi_rife
  SHARED
  kazumi_rife_bridge.cpp
  rife/rife.cpp
  rife/warp.cpp
)

target_include_directories(
  kazumi_rife
  PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/rife
)

target_compile_options(
  kazumi_rife
  PRIVATE
  -O3
  -ffast-math
)

target_link_libraries(
  kazumi_rife
  PRIVATE
  ncnn
  android
  log
)
