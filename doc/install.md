\page install Installation
\tableofcontents

Download MoonGen as instructed on the \ref download page.

\section installation Installation
1. Install the dependencies (see \ref dependencies)
2. git submodule update --init
3. ./build.sh
4. ./setup-hugetlbfs.sh
5. Run MoonGen from the build directory

Note: You can also use the script bind-interfaces.sh to bind all currently unused NICs (no routing table entry in the system) to DPDK/MoonGen. build.sh calls this script automatically. Use deps/dpdk/tools/dpdk_nic_bind.py to unbind NICs from the DPDK driver.

\section dependencies Dependencies

- gcc
- make
- cmake
- kernel headers (for the DPDK igb-uio driver)
