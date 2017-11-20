local list = require "cli.list"
local debug = require "cli.debug"
local help = require "cli.help"

local function configure(parser)
	list.configure(parser:command("list", "List all available flows."))
	debug.configure(parser:command("debug", "Dump variants of a single flow."))
	help.configure(parser:command("help", "Print help text for a topic."))
end

return configure
