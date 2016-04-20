-- configuration for all DPDK command line parameters
-- see DPDK documentation for more details
-- The DPDK EAL Parameters documentation is located at http://dpdk.org/doc/guides/testpmd_app_ug/run_app.html
-- MoonGen tries to choose reasonable defaults, so this config file can almost always be empty
-- Attention when running MoonGen in a VM that also uses another 'virtio' NIC e.g. for internet access.
-- In this case it is required to whitelist the PCI IDs used (one could probably also blacklist all others).
DPDKConfig {
	-- configure the cores to use, either as a bitmask or as a list
	-- default: all cores
	--cores = 0x0F, -- use the first 4 cores
	--cores = {0, 1, 3, 4},
	-- the number of memory channels (defaults to auto-detect)
	--memoryChannels = 2,

	-- the configures requried to run multiple DPDK applications. Refer to
	-- http://dpdk.org/doc/guides/prog_guide/multi_proc_support.html#running-multiple-independent-dpdk-applications
	-- for more information.

	-- a string to be the prefix, corresponding to EAL argument "--file-prefix"
	--fileprefix = "m1",

	-- A string to specify the socket memory allocation, corresponding to EAL argument "--socket-mem"
	--socketmem = "2048,2048",
	--
	-- PCI black list to avoid resetting PCI device assigned to other DPDK apps.
	-- Corresponding to ELA argument "--pci-blacklist"
	-- pciblack = {"0000:81:00.3","0000:81:00.1"},

	-- PCI white list to specify devices allocated to MoonGen.
	-- Corresponding to ELA argument "--pci-whitelist" or "-w"
	-- pciwhite = {"0000:81:00.3","0000:81:00.1"},

	-- disable hugetlb, see DPDK documentation for more information
	--noHugeTlbFs = true,
}
