local crawl = require "configcrawl"

local list = {}

local function _print_list(config)
	local flows = crawl(config, true)

	local files = setmetatable({}, {
		__index = function(tbl, key)
			local r = {}; tbl[key] = r; return r
		end
	})

	local count = 0
	for _,f in pairs(flows) do
		if f:getInstance{} then
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

function list.configure(parser)
	parser:argument("directory", "Change the base directory to search flows."):args("?"):default("flows")

	parser:action(function(args)
		_print_list(args.directory)
		os.exit(0)
	end)
end

return list
