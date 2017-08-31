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
    help.topics[args.topic](help_printer)
    table.remove(help_printer.result) -- remove last newline
    print(table.concat(help_printer.result))
    os.exit(0)
  end)
end

function help.addTopic(name, callback)
  help.topics[name] = callback
end

help.addTopic("topics", function()
  local result = { "Available topics:\n\n  " }

  for topic in pairs(help.topics) do
    if topic ~= "topics" then
      table.insert(result, topic)
      table.insert(result, ", ")
    end
  end

  table.remove(result)
  return table.concat(result)
end)

help.addTopic("options", require("configenv.flow").getOptionHelpString)

return help
