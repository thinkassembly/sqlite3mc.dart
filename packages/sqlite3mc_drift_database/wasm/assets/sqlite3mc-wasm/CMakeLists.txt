cmake_minimum_required(VERSION 3.22.1)
set(PROJECT_NAME "sqlite3mc")
project(${PROJECT_NAME} LANGUAGES C)

include(FetchContent)
FetchContent_Declare(
        sqlite3mc
                 URL https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v1.5.3/sqlite3mc-1.5.3-sqlite-3.39.4-amalgamation.zip
                 URL_HASH  SHA512=0edaa07b77368ee019c965951089a9f4f994de4cc0108980447fb99e2c17fe910201ea754bbbdc6a268012a6d1cfd8c9f64d12ae0e5db875e7f3e304c72366f1
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