project(PharmaScannerCxx)
cmake_minimum_required(VERSION 3.14)

set(PACKAGE_NAME PharmaScannerCxx)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 20)

# ── llama.cpp (static lib, CPU-only for Android) ────────────────────────────
set(GGML_OPENMP           OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN           OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE           OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES  OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS     OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON    OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS     OFF CACHE BOOL "" FORCE)

add_subdirectory(src/main/cpp/llama.cpp)

# ── Main shared library ─────────────────────────────────────────────────────
add_library(${PACKAGE_NAME} SHARED
    src/main/cpp/cpp-adapter.cpp
)

# llama_bridge — separate static lib so it links llama headers + symbols
add_library(llama_bridge SHARED
    src/main/cpp/llama_bridge.cpp
)

target_include_directories(llama_bridge PRIVATE
    src/main/cpp/llama.cpp/include
)

target_link_libraries(llama_bridge
    llama
    ggml
    log
)

# Pulls in all nitrogen-generated sources and links fbjni/ReactAndroid/NitroModules
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/PharmaScannerCxx+autolinking.cmake)

find_library(LOG_LIB log)

target_link_libraries(
    ${PACKAGE_NAME}
    ${LOG_LIB}
    android
)
