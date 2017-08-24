local help = {
  topics = {}
}

function help.configure(parser)
  parser:argument("topic", "Help topic to cover."):default("topics")

  parser:action(function(args)
    print(help.topics[args.topic]())
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
