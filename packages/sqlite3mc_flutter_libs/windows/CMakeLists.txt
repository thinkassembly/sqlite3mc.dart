cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "sqlite3mc_flutter_libs")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "sqlite3mc_flutter_libs_plugin")

# Essentially, the idea of this build script is to compile a sqlite3.dll
# and make Fluter bundle that with the final app.
# It looks like we can't avoid building a sqlite3_flutter_libs.dll too,
# but that's not on me.

add_library(${PLUGIN_NAME} SHARED
  "sqlite3mc_flutter_libs_plugin.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

include(FetchContent)

  FetchContent_Declare(
        sqlite3
        URL https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v1.5.4/sqlite3mc-1.5.4-sqlite-3.40.0-amalgamation.zip
        URL_HASH  SHA512=e2a677af79bc4331df6cd9c2549dd98cbca514ac7c0a7ac1c93b15051b7f5d33c2a3ec05e03793222cbbbbb3833054f6dbca49581e214572ab7dd5d47ece0ead
  )

FetchContent_MakeAvailable(sqlite3)

FetchContent_Declare(
  spellfix1
  URL https://raw.githubusercontent.com/sqlite/sqlite/branch-3.39/ext/misc/spellfix.c
  DOWNLOAD_NO_EXTRACT TRUE
)
FetchContent_MakeAvailable(spellfix1)

add_library(sqlite3mc SHARED
  "sqlite3_flutter.c"
  "${spellfix1_SOURCE_DIR}/spellfix.c"
)

target_include_directories(sqlite3mc PRIVATE "${sqlite3_SOURCE_DIR}")
target_compile_options(${PLUGIN_NAME} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")

# Note: Keep in sync with https://github.com/simolus3/sqlite-native-libraries/blob/master/sqlite3-native-library/cpp/CMakeLists.txt
target_compile_definitions(sqlite3mc PRIVATE
  SQLITE_ENABLE_FTS5
  SQLITE_ENABLE_RTREE
  SQLITE_DQS=0
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
  SQLITE_HAVE_LOCALTIME_R
  SQLITE_HAVE_LOCALTIME_S
)



# Ensure sqlite3 actually gets build
add_dependencies(${PLUGIN_NAME} sqlite3mc)

# List of absolute paths to libraries that should be bundled with the plugin
set(sqlite3mc_flutter_libs_bundled_libraries
  "$<TARGET_FILE:sqlite3mc>"
  PARENT_SCOPE
)