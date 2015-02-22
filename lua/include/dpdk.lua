--- high-level dpdk wrapper
local mod = {}
local ffi		= require "ffi"
local dpdkc		= require "dpdkc"

-- DPDK constants (lib/librte_mbuf/rte_mbuf.h)
-- TODO: import more constants here
mod.PKT_RX_IEEE1588_TMST	= 0x0400
mod.PKT_TX_IPV4_CSUM		= 0x1000
mod.PKT_TX_TCP_CKSUM     	= 0x2000 -- < TCP cksum of TX pkt. computed by NIC.
mod.PKT_TX_UDP_CKSUM		= 0x6000
mod.PKT_TX_NO_CRC_CSUM		= 0x0001

local function fileExists(f)
	local file = io.open(f, "r")
	if file then
		file:close()
	end
	return not not file
end

local cores

--- Inits DPDK. Called by MoonGen on startup.
function mod.init()
	-- register drivers
	dpdkc.register_pmd_drivers()
	-- TODO: support arbitrary dpdk configurations by allowing configuration in the form ["cmdLine"] = "foo"
	local cfgFileLocations = {
		"./dpdk-conf.lua",
		"./lua/dpdk-conf.lua",
		"../lua/dpdk-conf.lua",
		"/etc/moongen/dpdk-conf.lua"
	}
	local cfg
	for _, f in ipairs(cfgFileLocations) do
		if fileExists(f) then
			cfgScript = loadfile(f)
			setfenv(cfgScript, setmetatable({ DPDKConfig = function(arg) cfg = arg end }, { __index = _G }))
			local ok, err = pcall(cfgScript)
			if not ok then
				print("could not load DPDK config: " .. err)
				return false
			end
			if not cfg then
				print("config file does not contain DPDKConfig statement")
				return false
			end
			cfg.name = f
			break
		end
	end
	if not cfg then
		print("no DPDK config found, using defaults")
		cfg = {}
	end
	local coreMask
	if not cfg.cores then
		-- default: use all the cores
		local cpus = io.open("/proc/cpuinfo", "r")
		cfg.cores = {}
		for cpu in cpus:read("*a"):gmatch("processor	: (%d+)") do
			cfg.cores[#cfg.cores + 1] = tonumber(cpu)
		end
		cpus:close()
	end
	if type(cfg.cores) == "number" then
		coreMask = cfg.cores
		cores = {}
		-- TODO: support more than 32 cores but bit operations on 64 bit types are currently not supported in luajit
		for i = 0, 31 do
			if bit.band(coreMask, bit.lshift(1, i)) ~= 0 then
				cores[#cores + 1] = i
			end
		end
		if cfg.cores >= 2^32 then
			print("Warning: more than 32 cores are currently not supported in bitmask format, sorry")
			print("Use a table as a work-around")
			return
		end
	elseif type(cfg.cores) == "table" then
		cores = cfg.cores
		coreMask = 0
		for i, v in ipairs(cores) do
			coreMask = coreMask + 2^v
		end
	end
	local argv = { "MoonGen" }
	if cfg.noHugeTlbFs then
		argv[#argv + 1] = "--no-huge"
	end
	argv[#argv + 1] = ("-c0x%X"):format(coreMask)
	argv[#argv + 1] = "-n" .. (cfg.memoryChannels or 4) -- todo: auto-detect
	local argc = #argv
	dpdkc.rte_eal_init(argc, ffi.new("const char*[?]", argc, argv))
	return true
end

ffi.cdef[[
	struct lua_core_arg {
		enum { ARG_TYPE_STRING, ARG_TYPE_NUMBER, ARG_TYPE_BOOLEAN, ARG_TYPE_POINTER, ARG_TYPE_NIL, ARG_TYPE_OBJECT } arg_type;
		union {
			const char* str;
			double number;
			void* ptr;
			bool boolean;
		} arg;
	};
	void launch_lua_core(int core, int argc, struct lua_core_arg* argv[]);
]]


--- Launch a LuaJIT VM on a core with the given arguments.
--- TODO: use proper serialization and only pass strings
function mod.launchLuaOnCore(core, ...)
	local args = { ... }
	--- the (de-)serialization is ugly and needs a rewrite with a proper (de-)serialization library (Serpent?)
	local argsArray = ffi.new("struct lua_core_arg*[?]", #args)
	for i, v in ipairs(args) do
		argsArray[i - 1] = ffi.new("struct lua_core_arg")
		if type(v) == "string" then
			argsArray[i - 1].arg_type = ffi.C.ARG_TYPE_STRING
			argsArray[i - 1].arg.str = ffi.new("const char*", v)
		elseif type(v) == "number" then
			argsArray[i - 1].arg_type = ffi.C.ARG_TYPE_NUMBER
			argsArray[i - 1].arg.number = v
		elseif type(v) == "boolean" then
			argsArray[i - 1].arg_type = ffi.C.ARG_TYPE_BOOLEAN
			argsArray[i - 1].arg.boolean = v
		elseif type(v) == "cdata" or type(v) == "userdata" then
			argsArray[i - 1].arg_type = ffi.C.ARG_TYPE_POINTER
			argsArray[i - 1].arg.ptr = v
		else
			local objectOk = false
			if type(v) == "table" and getmetatable(v) then
				local t = getmetatable(v).__type
				if t == "device" or t == "rxQueue" or t == "txQueue" then
					-- TODO: this is obviously just a temporary work-around
					argsArray[i - 1].arg_type = ffi.C.ARG_TYPE_OBJECT
					argsArray[i - 1].arg.str = ffi.new("const char*", t .. "," ..
						(t == "device" and v.id or (v.id .. "," .. v.qid)))
					objectOk = true
				end
			end
			if not objectOk then
				error(("arguments of type %s are not supported for slave cores"):format(type(v)))
			end
		end
	end
	dpdkc.launch_lua_core(core, #args, argsArray)
end

--- launches the lua file on the first free core
function mod.launchLua(...)
	-- TODO: use dpdk iterator functions
	for i = 2, #cores do -- skip master
		local core = cores[i]
		if dpdkc.rte_eal_get_lcore_state(core) == dpdkc.WAIT then -- core is in WAIT state
			mod.launchLuaOnCore(core, mod.userScript, ...)
			return
		end
	end
	error("not enough cores to start this lua task")
end

ffi.cdef [[
	int usleep(unsigned int usecs);
]]

--- waits until all slave cores have finished their jobs
function mod.waitForSlaves()
	while true do
		local allCoresFinished = true
		for i = 2, #cores do -- skip master
			local core = cores[i]
			if dpdkc.rte_eal_get_lcore_state(core) == dpdkc.RUNNING then
				allCoresFinished = false
				break
			end
		end
		if allCoresFinished then
			return
		end
		ffi.C.usleep(100)
	end
end

function mod.getCores()
	return cores
end

--- get the CPU's TSC
function mod.getCycles()
	return dpdkc.rte_rdtsc()
end

--- get the TSC frequency
function mod.getCyclesFrequency()
	return tonumber(dpdkc.rte_get_tsc_hz())
end

--- gets the time in seconds
function mod.getTime()
	return tonumber(mod.getCycles()) / tonumber(mod.getCyclesFrequency())
end

--- set total run time of the test (to be called from master core on startup, shared between all cores)
function mod.setRuntime(time)
	dpdkc.set_runtime(time * 1000)
end

--- returns false once the app receives SIGTERM or SIGINT, the time set via setRuntime expires, or when a thread calls dpdk.stop()
function mod.running()
	return dpdkc.is_running() == 1 -- luajit-2.0.3 does not like bool return types (TRACE NYI: unsupported C function type)
end

--- request all tasks to exit
function mod.stop()
	dpdkc.set_runtime(0)
end

--- Delay by t milliseconds. Note that this does not sleep the actual thread;
--- the time is spent in a busy wait loop by DPDK.
function mod.sleepMillis(t)
	dpdkc.rte_delay_ms_export(t)
end

--- Delay by t microseconds. Note that this does not sleep the actual thread;
--- the time is spent in a busy wait loop by DPDK. This means that this sleep
--- is somewhat more accurate than relying on the OS.
function mod.sleepMicros(t)
	dpdkc.rte_delay_us_export(t)
end

--- Get the core and socket id for the current thread
function mod.getCore()
	return dpdkc.get_current_core(), dpdkc.get_current_socket()
end

return mod

