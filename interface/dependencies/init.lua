local dependencies = {}

for _,v in ipairs {
  "arp", "queueMac"
} do
  dependencies[v] =  require("dependencies." .. v)
end

return dependencies
