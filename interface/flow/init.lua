local errors = require "errors"
local log = require "log"

local Flow = {}
Flow.__index = Flow

local _option_list = {}
for _,v in ipairs {
	"rate", "ratePattern", "packetLength", "timestamp", "uid", "mode", "dataLimit", "timeLimit"
} do _option_list[v] =  require("options." .. v) end

function Flow.getOptionHelpString(help_printer)
	help_printer:section("Options")
	help_printer:body("List of options available when customizing flows using"
		.. " command line or configuration files.")

	help_printer:section("Units")
	help_printer:subsection("Size Units '\27[4m<prefix><unit>\27[0m'\n")
	help_printer:body("Prefix can be one of '\27[4m[k|M|G[i]]\27[0m'"
		.. " with the i marking an IEC-prefix using multiples of 1024 instead of 1000.")
	help_printer:body("Unit can be one of '\27[4m(B|bit|p)\27[0m',"
		.. " meaning byte, bit and packet respectively.")

	help_printer:subsection("Time Units")
	help_printer:body("Available time units are '\27[4m(ms|s|m|h)\27[0m'"
		.. " for millisecond, second, minute or hour.")

	for i,v in pairs(_option_list) do
		help_printer:section(i)
		help_printer:body(v.description)

		for _,fmt in ipairs(v.getHelp()) do
			if fmt[1] then
				help_printer:subsection(string.format("%s = \27[4m%s\27[0m", i, fmt[1]))
			else
				help_printer:subsection(i)
			end
			help_printer:body(fmt[2])
		end

		if v.configHelp then
			help_printer:subsection("Configuration\n")
			help_printer:body(v.configHelp)
		end
	end
end

function Flow.new(name, tbl, error)
	local self = { name = name, packet = tbl[2], parent = tbl.parent, configOpts = {} }
	tbl[1], tbl[2], tbl.parent = nil, nil, nil

	-- check and copy options
	for i,v in pairs(tbl) do
		if not _option_list[i] then
			error(3, "Unknown field %q in flow %q.", i, name)
		else
			self.configOpts[i] = v
		end
	end

	-- inherit packet and options
	local parent = self.parent
	if type(parent) == "table" then
		self.packet:inherit(parent.packet)
		for i in pairs(_option_list) do
			self[i] = self[i] or parent[i]
		end
	end

	return setmetatable(self, { __index = Flow })
end

function Flow:getPacketLength(finalLength)
	local size = self.results.packetLength
	if not size then
		size = _option_list.packetLength.parse(self,
			self.options.packetLength or self.packetLength, errors()) or 0
	end

	if finalLength then
		return size + 4
	end
	return size
end

local function _cbr_to_delay(cbr, psize)
	-- cbr      => mbit/s        => bit/1000ns
	-- psize    => b/p           => 8bit/p
	return 8000 * psize / cbr -- => ns/p
end

function Flow:getDelay()
	local cbr = self.results.rate
	if cbr then
		return _cbr_to_delay(cbr, self:getPacketLenth(true))
	end
end

function Flow:getInstance(options, inst)
	inst = inst or {}
	inst.options, inst.results = options, {}
	setmetatable(inst, { __index = self })

	local error = inst:prepare()

	for i in pairs(options) do
		error:assert(_option_list[i], "Unknown option '%s'.", i)
	end

	if #error > 0 then
		log:error("Found %d errors while preparing flow %s:", #error, self.name)
		error:print(nil, log.warn, log)
	end

	if error.valid then
		return inst
	end
end

function Flow:prepare()
	local error = errors()
	error.defaultLevel = -1

	for name, opt in pairs(_option_list) do
		local val = self.options[name] or self.configOpts[name]
		error:setPrefix("Option '%s': ", name)
		self.results[name] = opt.parse(self, val, error)
	end

	error:setPrefix()
	self.packet:prepare(error)
	return error
end

return Flow
