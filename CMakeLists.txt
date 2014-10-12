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
	ethdev       rte_distributor  rte_kni     rte_mbuf      rte_pmd_bond   rte_pmd_ring         rte_power  rte_timer
	rte_acl      rte_eal          rte_kvargs  rte_mempool   rte_pmd_e1000  rte_pmd_virtio_uio   rte_ring
	rte_cfgfile  rte_hash         rte_lpm     rte_meter     rte_pmd_i40e   rte_pmd_vmxnet3_uio  rte_sched
	rte_cmdline  rte_ip_frag      rte_malloc  rte_pipeline  rte_pmd_ixgbe  rte_port             rte_table
)

SET(LUAJIT_LIBS
	libluajit-5.1.so
)

SET(ALL_LIBS
	-Wl,--start-group ${DPDK_LIBS} -Wl,--end-group
	pthread dl rt
	${LUAJIT_LIBS}
)

INCLUDE_DIRECTORIES(
	 ${CMAKE_CURRENT_SOURCE_DIR}/dpdk/x86_64-native-linuxapp-gcc/include
	 ${CMAKE_CURRENT_SOURCE_DIR}/dpdk/lib/librte_pmd_ixgbe/ixgbe
)

LINK_DIRECTORIES(
	${CMAKE_CURRENT_SOURCE_DIR}/dpdk/x86_64-native-linuxapp-gcc/lib
)

ADD_EXECUTABLE(${PRJ} ${FILES})
TARGET_LINK_LIBRARIES(${PRJ} ${ALL_LIBS})


FILE(GLOB LUA_FILES ${CMAKE_SOURCE_DIR}/lua/*)

FILE(COPY ${LUA_FILES} DESTINATION . PATTERN "*.svn" EXCLUDE) 

