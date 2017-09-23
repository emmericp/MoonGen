local options = {}

for _,v in ipairs {
	"rate", "ratePattern", "timestamp", "uid", "mode", "dataLimit", "timeLimit"
} do
  options[v] =  require("options." .. v)
end

return options
