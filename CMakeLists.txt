CMAKE_MINIMUM_REQUIRED(VERSION 2.8)

SET(CMAKE_CXX_FLAGS "-Wall -Wextra -Wno-unused-parameter -g -O2 -std=gnu++11 -march=native -msse4.2 -I${CMAKE_CURRENT_SOURCE_DIR}/src")
SET(CMAKE_C_FLAGS "-Wall -Wextra -Wno-unused-parameter -g -O2 -std=gnu99 -march=native -msse4.2")
SET(CMAKE_EXE_LINKER_FLAGS "-rdynamic") # to access functions from luajit

SET(PRJ MoonGen)

SET(FILES
	src/main.c
	src/memory.c
	src/task.c
	src/device.c
	src/util.c
	src/lifecycle.c
)

SET(DPDK_LIBS
	rte_sched rte_mbuf rte_eal rte_lpm rte_cmdline rte_hash rte_malloc 
	rte_mempool rte_ring rte_pmd_ring rte_pmd_e1000 rte_pmd_ixgbe rte_timer rte_pmd_vmxnet3_uio rte_pmd_virtio_uio ethdev 
)

SET(LUAJIT_LIBS
	libluajit-5.1.so
)

SET(ALL_LIBS
	${DPDK_LIBS} pthread dl rt
	${LUAJIT_LIBS}
)

INCLUDE_DIRECTORIES(
	 ${CMAKE_CURRENT_SOURCE_DIR}/dpdk/x86_64-default-linuxapp-gcc/include
	 ${CMAKE_CURRENT_SOURCE_DIR}/dpdk/lib/librte_pmd_ixgbe/ixgbe
)

LINK_DIRECTORIES(
	${CMAKE_CURRENT_SOURCE_DIR}/dpdk/x86_64-default-linuxapp-gcc/lib
)

ADD_EXECUTABLE(${PRJ} ${FILES})
TARGET_LINK_LIBRARIES(${PRJ} ${ALL_LIBS})


FILE(GLOB LUA_FILES ${CMAKE_SOURCE_DIR}/lua/*)

FILE(COPY ${LUA_FILES} DESTINATION . PATTERN "*.svn" EXCLUDE) 

