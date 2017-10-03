local help = {
	topics = {}
}

local function formatIndented(result, cols, indent, text)
	if type(indent) == "number" then
		indent = string.rep(" ", indent)
	end

	table.insert(result, string.match(text, "^(\n*)"))
	for line, nl in string.gmatch(text, "([^\n]+)([\n]*)") do
		local current, nextSpace = 0, ""
		table.insert(result, indent)

		table.insert(result, string.match(line, "^(%s*)"))
		for w, s in string.gmatch(line, "(%S+)(%s*)") do
			local next = current + #w + #nextSpace

			if next > cols then
				table.insert(result, "\n")
				table.insert(result, indent)
				current, nextSpace = 0, ""
			else
				current = next
			end

			table.insert(result, nextSpace)
			nextSpace = s

			table.insert(result, w)
		end

		table.insert(result, nl)
	end
end

local help_printer = {
	result = {}, bodyLevel = 0,
	indent = 6, margin = 6
}

function help_printer:section(title)
	table.insert(self.result, string.upper(title))
	table.insert(self.result, "\n")
	self.bodyLevel = 1
end

function help_printer:subsection(title)
	table.insert(self.result, string.rep(" ", self.indent))
	table.insert(self.result, title)
	table.insert(self.result, "\n")
	self.bodyLevel = 2
end

function help_printer:body(text)
	local bodycols = self.cols - self.indent * self.bodyLevel - self.margin
	formatIndented(self.result, bodycols, self.indent * self.bodyLevel, text)
	table.insert(self.result, "\n\n")
end

function help.configure(parser)
	parser:argument("topic", "Help topic to cover."):default("topics")

	parser:action(function(args)
		local tput = io.popen("tput cols")
		local cols = tonumber(tput:read())
		tput:close()

		help_printer.cols = cols
		help.topics[string.lower(args.topic)](help_printer)
		table.remove(help_printer.result) -- remove last newline
		print(table.concat(help_printer.result))
		os.exit(0)
	end)
end

function help.addTopic(name, callback)
	help.topics[name] = callback
end

help.addTopic("options", function(hp)
	hp:section("Options")
	hp:body("List of options available when customizing flows using"
		.. " command line or configuration files.")

	hp:section("Units")
	hp:subsection("Size Units '\27[4m<prefix><unit>\27[0m'\n")
	hp:body("Prefix can be one of '\27[4m[k|M|G[i]]\27[0m'"
		.. " with the i marking an IEC-prefix using multiples of 1024 instead of 1000.")
	hp:body("Unit can be one of '\27[4m(B|bit|p)\27[0m',"
		.. " meaning byte, bit and packet respectively.")

	hp:subsection("Time Units")
	hp:body("Available time units are '\27[4m(ms|s|m|h)\27[0m'"
		.. " for millisecond, second, minute or hour.")

	local options = require "options"
	local names = {}

	for i in pairs(options) do table.insert(names, i) end
	table.sort(names)

	for n = 1, #names do
		local i = names[n]
		local v = options[i]

		hp:section(i)
		hp:body(v.description)

		for _,fmt in ipairs(v.usage) do
			if fmt[1] then
				hp:subsection(string.format("%s = \27[4m%s\27[0m", i, fmt[1]))
			else
				hp:subsection(i)
			end
			hp:body(fmt[2])
		end

		if v.configHelp then
			hp:subsection("Configuration\n")
			hp:body(v.configHelp)
		end
	end
end)

help.addTopic("topics", function(hp)
	local result = {}

	for topic in pairs(help.topics) do
		if topic ~= "topics" then
			table.insert(result, topic)
		end
	end
	table.sort(result)

	hp:section("Available Topics")
	hp:body(table.concat(result, ", "))
end)

local flowExample = [[
Flow{"name", Packet.Udp{
		udpSrc = 1234,
		ip4Src = ip"10.100.1.1",
	},
	rate = 1000,
}]]

help.addTopic("configuration", function(hp)
	hp:section("Directory Structure")
	hp:body("Config files are assumed to reside in a single directory. Subdirectories are ignored."
		.. " All files in the directory will be treated as Lua sourcecode and scanned for valid flows.")

	hp:section("File Contents")
	hp:body("All files have access to Lua functions in string, table and math,"
		.. " as well as some globals from Lua and libmoon.")

	hp:subsection("Flows")
	hp:body("Flows consist of a name and a packet definition."
		.. " They also allow setting default values for all options.")

	hp:subsection("Example")
	hp:body(flowExample)

	hp:subsection("Closures")
	hp:body("Some options allow functions to be passed. Keep in mind, that each flow will typically"
		.. " be run in its own Lua vm, so closures will not persist across flows.")
end)

return help
