cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "sqlite3mc_flutter_libs")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "sqlite3mc_flutter_libs_plugin")

include(FetchContent)
FetchContent_Declare(
        sqlite3
        URL https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v1.4.8/sqlite3mc-1.4.8-sqlite-3.39.2-amalgamation.zip
        URL_HASH  SHA512=d7127734007cb1623e49808ca024ba5d5b07bbe1306f90d0c3a7e5d26daf4e6c17a158f7b1b394c1c54bfb710c0b13104867c95358f7433650075a81c644663c
)
FetchContent_MakeAvailable(sqlite3)

add_library(${PLUGIN_NAME} SHARED
  "sqlite3_flutter_libs_plugin.cc"
  "${sqlite3_SOURCE_DIR}/sqlite3mc_amalgamation.c"
)

# Not applying the standard settings because we compile sqlite3
# which fails with -Wall -Werror. But we apply most of them:
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)

# need aes feature enabled.
# also added switch -Wno-pointer-sign to suppress a couple annoying warnings.
# can remove when fixed upstream

target_compile_options(${PLUGIN_NAME} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>" -maes -Wno-pointer-sign)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)


# Sqlite3 Multiple Ciphers won't build with SQLITE_USER_AUTHENTICATION and SQLITE_OMIT_SHARED_CACHE see: https://github.com/utelle/SQLite3MultipleCiphers/issues/42
# Note: Keep in sync with https://github.com/simolus3/sqlite-native-libraries/blob/master/sqlite3-native-library/cpp/CMakeLists.txt
target_compile_definitions(${PLUGIN_NAME} PRIVATE
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
