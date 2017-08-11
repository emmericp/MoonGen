local crawl = require "configcrawl"
local validator = require "validator"

return function(config)
	local flows = crawl(config, true)

	local files = setmetatable({}, {
		__index = function(tbl, key)
			local r = {}; tbl[key] = r; return r
		end
	})

	local count = 0
	for _,f in pairs(flows) do
		local val = validator()
		f:validate(val)
		if val.valid then
			table.insert(files[f.file], f)
			count = count + 1
		end
	end

	if count == 0 then
		print "No flows found."
		return
	end

	local fmt = "  %-58s%-10s%-10d"
	print(string.format("%-60s%-10s%-10s", "NAME", "PROTOCOL", "DYNVARS"))
	print(string.rep("=", 80))
	for i,v in pairs(files) do
		print(i)
		for _,f in ipairs(v) do
			print(string.format(fmt, f.name, f.packet.proto, #f.packet.dynvars))
		end
	end
end
