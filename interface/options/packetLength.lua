local option = {}

option.description = "Redefine the actualy size of sent packets using the command line."
option.configHelp = "Designed for command line usage only. Use pktLength in the Packet"
  .. " descriptor, when editing configuration files."

function option.getHelp()
  return { { "<integer>", "New size in bytes." } }
end

function option.parse(self, packetLength, error)
  if type(packetLength) == "string" then
    packetLength = error:assert(tonumber(packetLength),
      "Value needs to be a valid integer.")
  end

  local t = type(packetLength)
  local valid
  if t == "number" then
    valid = error:assert(packetLength >= self.packet.minSize,
      "Invalid value. Minimum size for %s is %d", self.packet.proto, self.packet.minSize)
  else
    valid = error:assert(t == "nil", "Invalid argument. String or number expected, got %s.", t)
  end

  return valid and packetLength or self.packet.fillTbl.pktLength
end

return option
