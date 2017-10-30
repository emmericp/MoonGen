local Flow = require "flow"
local lfs = require "syscall.lfs"
local log = require "log"

local list = {}

local function _print_list(config)
	for _,v in ipairs(config) do
		local type = lfs.attributes(v, "mode")
		if type == "file" then
			Flow.crawlFile(v)
		elseif type == "directory" then
			Flow.crawlDirectory(v)
		else
			log:error("Entry %s is neither file nor directory.", v)
		end
	end

	local files = setmetatable({}, {
		__index = function(tbl, key)
			local r = {}; tbl[key] = r; return r
		end
	})

	local count = 0
	for _,f in pairs(Flow.flows) do
		if Flow.getInstance(f.name, nil, {}, nil, { rx = {1}, tx = {1} }) then
			table.insert(files[f.file], f)
			count = count + 1
		end
		table.sort(files[f.file], function(a,b) return a.name < b.name end)
	end

	if count == 0 then
		print "No flows found."
		return
	end

	local fmt = "  %-58s%-10s%-5d%-5d"
	print(string.format("%-60s%-10s%-5s%-5s", "NAME", "PROTOCOL", "DYN", "DEP"))
	print(string.rep("=", 80))
	for i,v in pairs(files) do
		print(i)
		for _,f in ipairs(v) do
			print(string.format(fmt, f.name, f.packet.proto, #f.packet.dynvars, #f.packet.depvars))
		end
	end
end

function list.configure(parser)
	parser:argument("entries", "List of files and directories to search for flows in."):args("*"):default("flows")

	parser:action(function(args)
		_print_list(args.entries or { "flows" })
		os.exit(0)
	end)
end

return list
