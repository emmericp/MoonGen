cmake_minimum_required(VERSION 2.8)
project(MoonGen C CXX)

set(CMAKE_CXX_FLAGS "-fno-stack-protector -Wall -Wextra -Wno-unused-parameter -g -O3 -std=gnu++11 -march=native -msse4.2")
set(CMAKE_C_FLAGS "-fno-stack-protector -Wall -Wextra -Wno-unused-parameter -g -O3 -std=gnu11 -march=native -msse4.2")
set(CMAKE_EXE_LINKER_FLAGS "-rdynamic")

set(PHOBOS_BUILD_LIBRARY true)
add_definitions(-DPHOBOS_LUA_MAIN_MODULE="moongen-main")
add_subdirectory(phobos)


include_directories(
	${CMAKE_CURRENT_SOURCE_DIR}/src
	${CMAKE_CURRENT_SOURCE_DIR}/lib
	${CMAKE_CURRENT_SOURCE_DIR}/phobos/deps/dpdk/x86_64-native-linuxapp-gcc/include
	${CMAKE_CURRENT_SOURCE_DIR}/phobos/deps/luajit/src
	${CMAKE_CURRENT_SOURCE_DIR}/phobos/lib
	${CMAKE_CURRENT_SOURCE_DIR}/phobos/src
)

set(files
	src/moongen-main
	src/software-timestamping
	src/crc-rate-limiter
)

set(libraries
	-Wl,--whole-archive phobos -Wl,--no-whole-archive
)

link_directories(
	${CMAKE_CURRENT_BINARY_DIR}/phobos
	${CMAKE_CURRENT_SOURCE_DIR}/phobos/deps/dpdk/x86_64-native-linuxapp-gcc/lib
	${CMAKE_CURRENT_SOURCE_DIR}/phobos/deps/luajit/usr/local/lib
)

add_executable(MoonGen ${files})
target_link_libraries(MoonGen ${libraries})

