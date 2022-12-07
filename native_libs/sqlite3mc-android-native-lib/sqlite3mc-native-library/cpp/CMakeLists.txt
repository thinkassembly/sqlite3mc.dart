cmake_minimum_required(VERSION 3.22.1)



project(
    sqlite3mc_native_library
    VERSION 3
    LANGUAGES C CXX
)



include(FetchContent)
FetchContent_Declare(
        sqlite3mc
        URL https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v1.4.8/sqlite3mc-1.4.8-sqlite-3.39.2-amalgamation.zip
        URL_HASH  SHA512=d7127734007cb1623e49808ca024ba5d5b07bbe1306f90d0c3a7e5d26daf4e6c17a158f7b1b394c1c54bfb710c0b13104867c95358f7433650075a81c644663c
)
FetchContent_MakeAvailable(sqlite3mc)

set(CMAKE_C_FLAGS "-O3")


add_library(sqlite3mc SHARED
  "${sqlite3mc_SOURCE_DIR}/sqlite3mc_amalgamation.c"
)
target_include_directories(sqlite3mc PRIVATE ${sqlite3mc_SOURCE_DIR}/include)

add_definitions(-DHAVE_NEON_X86=1 -DHAVE_NEON=1)

# Not applying the standard settings because we compile sqlite3
# which fails with -Wall -Werror. But we apply most of them:

# need aes feature enabled.
# also added switch -Wno-pointer-sign to suppress a couple annoying warnings.
# can remove when fixed upstream

target_compile_options(sqlite3mc PRIVATE  -Wno-pointer-sign -mfpu=neon -maes)


target_include_directories(sqlite3mc INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"   "${CMAKE_CURRENT_SOURCE_DIR}" )

target_include_directories(sqlite3mc PRIVATE "${PROJECT_SOURCE_DIR}/")



# Sqlite3 Multiple Ciphers won't build with SQLITE_USER_AUTHENTICATION and SQLITE_OMIT_SHARED_CACHE see: https://github.com/utelle/SQLite3MultipleCiphers/issues/42

target_compile_definitions(sqlite3mc PUBLIC
    SQLITE_DQS=0
    SQLITE_THREADSAFE=2
    SQLITE_DEFAULT_MEMSTATUS=0
    SQLITE_TEMP_STORE=2
    SQLITE_MAX_EXPR_DEPTH=0
    SQLITE_OMIT_AUTHORIZATION
    SQLITE_OMIT_DECLTYPE
    SQLITE_OMIT_DEPRECATED
    SQLITE_OMIT_GET_TABLE
    SQLITE_OMIT_LOAD_EXTENSION
    SQLITE_OMIT_PROGRESS_CALLBACK
    SQLITE_OMIT_SHARED_CACHE
    SQLITE_OMIT_TCL_VARIABLE
    SQLITE_OMIT_TRACE
    SQLITE_USE_ALLOCA
    SQLITE_UNTESTABLE
    SQLITE_HAVE_ISNAN
    SQLITE_ENABLE_FTS5
    SQLITE_ENABLE_JSON1
    SQLITE_ENABLE_RTREE
    SQLITE_USER_AUTHENTICATION=0
)