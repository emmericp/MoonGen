local ffi = require "ffi"
ffi.cdef [[
struct mg_bitmask{
  uint16_t size;
  uint16_t n_blocks;
  uint64_t mask[0];
};
struct mg_bitmask * mg_bitmask_create(uint16_t size);
void mg_bitmask_free(struct mg_bitmask * mask);
void mg_bitmask_set_all_one(struct mg_bitmask * mask);
uint8_t mg_bitmask_get_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_set_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_clear_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_and(struct mg_bitmask * mask1, struct mg_bitmask * mask2);
void mg_bitmask_or(struct mg_bitmask * mask1, struct mg_bitmask * mask2);
]]


mod = {}

local mg_bitMask = {}
--mg_bitMask.__index = mg_bitMask

--- Create a Bitmask
-- The mask is internally built from blocks of 64bit integers. Hence a Bitmask
-- of a size <<64 yields significant overhead
-- @param size Size of the bitmask in number of bits
-- @return Wrapper table around the bitmask
function mod.createBitMask(size)
  return setmetatable({
    bitmask = ffi.gc(ffi.C.mg_bitmask_create(size), function (self)
      print("I HAVE BEEN DESTRUCTED")
      ffi.C.mg_bitmask_free(self)
    end )
  }, mg_bitMask)
end

-- TODO: think of a better solution - meh
function mod.linkToArray(bitmasks)
  array = ffi.new("struct mg_bitmask*[?]", #bitmasks)
  local i = 0
  for _,m in pairs(bitmasks) do
    array[i] = m.bitmask
    i = i + 1
  end
  return array
end

--- Sets all bits in a bitmask to 1
function mg_bitMask:setAll()
  ffi.C.mg_bitmask_set_all_one(self.bitmask)
  return self
end

-- TODO: implement wrappers for bitlogic functions

--- Index metamethod for mg_bitMask
-- @param x Bit index. Index starts at 1 according to the LUA standard (1 indexes the first bit in the bitmask)
-- @return For numeric indices: true, when corresponding bit is 1, false otherwise.
function mg_bitMask:__index(x)
  -- access
  --print(" bit access")
  --print(" type " .. type(x))
  --print(" x = " .. tostring(x))
  if(type(x) == "number") then
    return (ffi.C.mg_bitmask_get_bit(self.bitmask, x - 1) ~= 0)
  else
    return mg_bitMask[x]
  end
end

--- Newindex metamethod for mg_bitMask
-- @param x Bit index. Index starts at 1 according to the LUA standard (1 indexes the first bit in the bitmask)
-- @param y Assigned value to the index (bit is cleared for y==0 and set otherwise)
function mg_bitMask:__newindex(x, y)
  --print ("new index")
  if(y == 0) then
    -- clear bit
    --print("clear")
    return ffi.C.mg_bitmask_clear_bit(self.bitmask, x - 1)
  else
    -- set bit
    --print("set")
    return ffi.C.mg_bitmask_set_bit(self.bitmask, x - 1)
  end
end

do
	local function it(self, i)
		if i >= self.bitmask.size then
			return nil
		end
		return i + 1, self[i+1]
	end

	function mg_bitMask.__ipairs(self)
		return it, self, 0
	end
end

return mod
