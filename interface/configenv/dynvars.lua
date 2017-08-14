local dynvar = {}
local _mt_dynvar = { __index = dynvar }

local function _new_dynvar(pkt, var, func)
	local self = { pkt = pkt, var = var, func = func }
	self.value = func() -- NOTE arp will execute in master

	return setmetatable(self, _mt_dynvar)
end

function dynvar:update()
	local v = self.func()
	self.value = v
	return v
end

-- TODO improve apply
function dynvar:apply(pkt)
	local var = pkt[self.pkt][self.var]
	if type(var) == "cdata" then
		var:set(self.value)
	else
		pkt[self.pkt][self.var] = self.value
	end
end

function dynvar:updateApply(pkt)
	dynvar.update(self)
	local var = pkt[self.pkt][self.var]
	if type(var) == "cdata" then
		var:set(self.value)
	else
		pkt[self.pkt][self.var] = self.value
	end
end

local dynvars, dv_final = {}, {}
local _mt_dynvars = { __index = dynvars }
local _mt_dv_final = { __index = dv_final }

function dynvars.new()
	local self = {
		index = {}, count = 0
	}
	return setmetatable(self, _mt_dynvars)
end

local function _add_dv(self, index, dv)
	table.insert(self, dv)
	self.index[index] = dv
	self.count = self.count + 1
end

function dynvars:add(pkt, var, func)
	local dv = _new_dynvar(pkt, var, func)
	_add_dv(self, pkt .. "_" .. var, dv)
	return dv
end

function dynvars:inherit(other)
	for i,v in pairs(other.index) do
		if not self.index[i] then
			_add_dv(self, i, v)
		end
	end
end

function dynvars:finalize()
	setmetatable(self, _mt_dv_final)
end

function dv_final:updateAll()
	for i = 1, self.count do
		dynvar.update(self[i])
	end
end

function dv_final:applyAll(pkt)
	for i = 1, self.count do
		dynvar.apply(self[i], pkt)
	end
end

function dv_final:updateApplyAll(pkt)
	for i = 1, self.count do
		dynvar.updateApply(self[i], pkt)
	end
end

return dynvars
