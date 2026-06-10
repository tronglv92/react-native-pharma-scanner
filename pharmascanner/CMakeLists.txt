project(PharmaScannerCxx)
cmake_minimum_required(VERSION 3.14)

set(PACKAGE_NAME PharmaScannerCxx)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 20)

# ── llama.cpp (CPU-only for Android) ─────────────────────────────────────────
set(GGML_OPENMP           OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN           OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE           OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES  OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS     OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON    OFF CACHE BOOL "" FORCE)

# Build backends as dynamic libraries so the best CPU variant is selected at runtime.
# GGML_CPU_ALL_VARIANTS builds ARM-optimized variants (DOTPROD, MATMUL_INT8, SVE2, etc.)
# that are auto-selected based on the device's CPU capabilities.
set(BUILD_SHARED_LIBS      ON  CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL       ON  CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS ON  CACHE BOOL "" FORCE)

add_subdirectory(src/main/cpp/llama.cpp)

# ── mtmd (multimodal) library ────────────────────────────────────────────────
# Cannot use add_subdirectory because the mtmd CMakeLists.txt unconditionally
# builds CLI executables that depend on llama-common (which we have disabled).
# Instead, define a custom library target with the mtmd source files directly.
set(MTMD_DIR src/main/cpp/llama.cpp/tools/mtmd)

add_library(mtmd SHARED
    ${MTMD_DIR}/mtmd.cpp
    ${MTMD_DIR}/mtmd-audio.cpp
    ${MTMD_DIR}/mtmd-image.cpp
    ${MTMD_DIR}/mtmd-helper.cpp
    ${MTMD_DIR}/clip.cpp
    ${MTMD_DIR}/models/cogvlm.cpp
    ${MTMD_DIR}/models/conformer.cpp
    ${MTMD_DIR}/models/dotsocr.cpp
    ${MTMD_DIR}/models/exaone4_5.cpp
    ${MTMD_DIR}/models/gemma4a.cpp
    ${MTMD_DIR}/models/gemma4v.cpp
    ${MTMD_DIR}/models/gemma4ua.cpp
    ${MTMD_DIR}/models/gemma4uv.cpp
    ${MTMD_DIR}/models/glm4v.cpp
    ${MTMD_DIR}/models/granite-speech.cpp
    ${MTMD_DIR}/models/hunyuanvl.cpp
    ${MTMD_DIR}/models/internvl.cpp
    ${MTMD_DIR}/models/kimivl.cpp
    ${MTMD_DIR}/models/kimik25.cpp
    ${MTMD_DIR}/models/nemotron-v2-vl.cpp
    ${MTMD_DIR}/models/llama4.cpp
    ${MTMD_DIR}/models/llava.cpp
    ${MTMD_DIR}/models/minicpmv.cpp
    ${MTMD_DIR}/models/paddleocr.cpp
    ${MTMD_DIR}/models/pixtral.cpp
    ${MTMD_DIR}/models/qwen2vl.cpp
    ${MTMD_DIR}/models/qwen3vl.cpp
    ${MTMD_DIR}/models/mimovl.cpp
    ${MTMD_DIR}/models/qwen3a.cpp
    ${MTMD_DIR}/models/step3vl.cpp
    ${MTMD_DIR}/models/siglip.cpp
    ${MTMD_DIR}/models/whisper-enc.cpp
    ${MTMD_DIR}/models/deepseekocr.cpp
    ${MTMD_DIR}/models/deepseekocr2.cpp
    ${MTMD_DIR}/models/mobilenetv5.cpp
    ${MTMD_DIR}/models/youtuvl.cpp
    ${MTMD_DIR}/models/yasa2.cpp
)

target_include_directories(mtmd PUBLIC  ${MTMD_DIR})
target_include_directories(mtmd PRIVATE src/main/cpp/llama.cpp)
target_include_directories(mtmd PRIVATE src/main/cpp/llama.cpp/vendor)
target_link_libraries(mtmd PUBLIC ggml llama)
target_compile_features(mtmd PRIVATE cxx_std_17)
set_target_properties(mtmd PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(mtmd PRIVATE LLAMA_BUILD)
target_compile_definitions(mtmd PUBLIC  LLAMA_SHARED)

if (NOT MSVC)
    target_compile_options(mtmd PRIVATE -Wno-cast-qual)
endif()
if (ANDROID)
    target_compile_options(mtmd PRIVATE -Wno-missing-prototypes)
endif()

# ── Main shared library ─────────────────────────────────────────────────────
add_library(${PACKAGE_NAME} SHARED
    src/main/cpp/cpp-adapter.cpp
)

# llama_bridge — separate shared lib so it links llama + mtmd headers + symbols
add_library(llama_bridge SHARED
    src/main/cpp/llama_bridge.cpp
)

target_include_directories(llama_bridge PRIVATE
    src/main/cpp/llama.cpp/include
    src/main/cpp/llama.cpp/ggml/include
    ${MTMD_DIR}
)

target_link_libraries(llama_bridge
    llama
    ggml
    mtmd
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
