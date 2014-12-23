-- configuration for all DPDK command line parameters
-- see DPDK documentation for more details
-- MoonGen tries to choose reasonable defaults, so this config file can almost always be empty
DPDKConfig {
	-- configure the cores to use, either as a bitmask or as a list
	-- default: all cores
	--cores = 0x0F, -- use the first 4 cores
	--cores = {0, 1, 3, 4},
	
	-- the number of memory channels (defaults to auto-detect)
	--memoryChannels = 2,

	-- disable hugetlb, see DPDK documentation for more information
	--noHugeTlbFs = true,
}

