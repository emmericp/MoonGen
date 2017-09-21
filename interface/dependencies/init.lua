local dependencies = {}

for _,v in ipairs {
  "queueMac"
} do
  dependencies[v] =  require("dependencies." .. v)
end

return dependencies
