cmake_minimum_required(VERSION 3.22.1)
set(PROJECT_NAME "sqlite3mc")
project(${PROJECT_NAME} LANGUAGES C)

include(FetchContent)
FetchContent_Declare(
        sqlite3mc
        URL https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v1.5.4/sqlite3mc-1.5.4-sqlite-3.40.0-amalgamation.zip
        URL_HASH  SHA512=e2a677af79bc4331df6cd9c2549dd98cbca514ac7c0a7ac1c93b15051b7f5d33c2a3ec05e03793222cbbbbb3833054f6dbca49581e214572ab7dd5d47ece0ead
)
FetchContent_MakeAvailable(sqlite3mc)

set(wasm_visibility "__attribute__((visibility(\"default\")))")

macro(base_sqlite3mc_target name)
    add_executable(${name}
  "${sqlite3mc_SOURCE_DIR}/sqlite3mc_amalgamation.c"
            os_web.c
            helpers.c
    )



    target_link_options(${name} PRIVATE  -nostartfiles  -Wl,--import-memory -Wl,--no-entry -Wl,--export-dynamic -Wl,--allow-undefined )
    target_include_directories(${name} PRIVATE "${PROJECT_SOURCE_DIR}/")
    target_include_directories(${name} PRIVATE ${sqlite3mc_SOURCE_DIR})
    target_compile_definitions(${name} PRIVATE
        _HAVE_SQLITE_CONFIG_H
        SQLITE_API=${wasm_visibility}
    )
endmacro()

base_sqlite3mc_target(sqlite3mc_debug)
target_sources(sqlite3mc_debug PRIVATE vfstrace.c)
target_compile_options(sqlite3mc_debug PRIVATE -g --sysroot=${CMAKE_SYSROOT} -Wno-pointer-sign)
target_compile_definitions(sqlite3mc_debug PRIVATE SQLITE_ENABLE_VFSTRACE)
set_target_properties(sqlite3mc_debug PROPERTIES OUTPUT_NAME "sqlite3mc" SUFFIX ".debug.wasm")

base_sqlite3mc_target(sqlite3mc_opt)
target_compile_options(sqlite3mc_opt PRIVATE  -O3 --sysroot=${wasi_sysroot} -Wno-pointer-sign)
set_target_properties(sqlite3mc_opt PROPERTIES OUTPUT_NAME "sqlite3mc" SUFFIX ".tmp.wasm")
add_custom_command(TARGET sqlite3mc_opt POST_BUILD
    COMMAND wasm-opt sqlite3mc.tmp.wasm -O4 -o sqlite3mc.wasm
)

add_custom_target(full)
add_custom_command(TARGET full COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3mc.wasm ${CMAKE_BINARY_DIR}/../../../../lib/assets/sqlite3mc.wasm)
add_custom_command(TARGET full COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3mc.debug.wasm ${CMAKE_BINARY_DIR}/../../../../lib/assets/sqlite3mc.debug.wasm)
add_dependencies(full sqlite3mc_debug sqlite3mc_opt)

add_custom_target(opt)
add_custom_command(TARGET opt COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3mc.wasm ${CMAKE_BINARY_DIR}/../../../lib/assets/sqlite3mc.wasm)
add_dependencies(opt sqlite3mc_opt)

add_custom_target(debug)
add_custom_command(TARGET debug COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3mc.debug.wasm ${CMAKE_BINARY_DIR}/../../../lib/assets/sqlite3mc.debug.wasm)
add_dependencies(debug sqlite3mc_debug )