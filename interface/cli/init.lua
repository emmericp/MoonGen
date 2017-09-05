local list = require "cli.list"
local debug = require "cli.debug"
local help = require "cli.help"

local function configure(parser)
	parser:description("Configuration based interface for MoonGen.")

	list.configure(parser:command("list", "List all available flows."))
	debug.configure(parser:command("debug", "Dump variants of a single flow."))
	help.configure(parser:command("help", "Print help text for a topic."))

	local send = parser:command("send", "Send one or more flows.")
	send:option("-c --config", "Config file directory."):default("flows")
	send:argument("flows", "List of flow names."):args "+"
end

return configure
