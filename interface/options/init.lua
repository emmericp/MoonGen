local options = {}

for _,v in ipairs {
	"rate", "ratePattern", "packetLength", "timestamp", "uid", "mode", "dataLimit", "timeLimit"
} do
  options[v] =  require("options." .. v)
end

return options
