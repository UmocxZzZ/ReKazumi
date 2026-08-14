cmake_minimum_required(VERSION 3.22.1)

project(rekazumi_framegen LANGUAGES CXX)

add_library(
    rekazumi_framegen
    SHARED
    rekazumi_framegen.cpp
)

find_library(vulkan_library vulkan REQUIRED)

target_compile_features(rekazumi_framegen PRIVATE cxx_std_17)
target_compile_definitions(
    rekazumi_framegen
    PRIVATE
    VK_USE_PLATFORM_ANDROID_KHR
)
target_compile_options(
    rekazumi_framegen
    PRIVATE
    -Wall
    -Wextra
    -Werror
)
target_link_libraries(rekazumi_framegen PRIVATE ${vulkan_library})
