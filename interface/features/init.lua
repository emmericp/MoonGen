local features = {}

for _,v in ipairs {
  "queueMac"
} do
  features[v] =  require("features." .. v)
end

return features
