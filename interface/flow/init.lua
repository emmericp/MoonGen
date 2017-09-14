local errors = require "errors"
local log = require "log"

local options = require "options"

local Flow = {}
Flow.__index = Flow

function Flow.new(name, tbl, error)
	local self = { name = name, packet = tbl[2], parent = tbl.parent, configOpts = {} }
	tbl[1], tbl[2], tbl.parent = nil, nil, nil

	-- check and copy options
	for i,v in pairs(tbl) do
		if not options[i] then
			error(3, "Unknown field %q in flow %q.", i, name)
		else
			self.configOpts[i] = v
		end
	end

	-- inherit packet and options
	local parent = self.parent
	if type(parent) == "table" then
		self.packet:inherit(parent.packet)
		for i in pairs(options) do
			self[i] = self[i] or parent[i]
		end
	end

	return setmetatable(self, { __index = Flow })
end

function Flow:getPacketLength(finalLength)
	local size = self.results.packetLength
	if not size then
		size = options.packetLength.parse(self,
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
		return _cbr_to_delay(cbr, self:getPacketLength(true))
	end
end

function Flow:getInstance(cli_options, inst)
	inst = inst or {}
	inst.options, inst.results = cli_options, {}
	setmetatable(inst, { __index = self })

	local error = inst:prepare()

	for i in pairs(cli_options) do
		error:assert(options[i], "Unknown option '%s'.", i)
	end

	if #error > 0 then
		log:error("Found %d errors while preparing flow %s:", #error, self.name)
		error:print(nil, log.warn, log)
	end

	if error.valid then
		return inst
	end
end

function Flow:prepare(final)
	local error = errors()
	error.defaultLevel = -1

	for name, opt in pairs(options) do
		local val = self.options[name] or self.configOpts[name]
		error:setPrefix("Option '%s': ", name)
		self.results[name] = opt.parse(self, val, error)
	end

	error:setPrefix()
	self.packet:prepare(final, error)
	return error
end

return Flow
