
local bor, band, bnot, rshift, lshift, bswap = bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift, bit.bswap

function printf(str, ...)
	return print(str:format(...))
end

function errorf(str, ...)
	error(str:format(...), 2)
end

function mapVarArg(f, ...)
	local l = { ... }
	for i, v in ipairs(l) do
		l[i] = f(v)
	end
	return unpack(l)
end

function map(f, t)
	for i, v in ipairs(t) do
		t[i] = f(v)
	end
	return t
end

function tostringall(...)
	return mapVarArg(tostring, ...)
end

function tonumberall(...)
	return mapVarArg(tonumber, ...)
end

function bswap16(n)
	return bor(rshift(n, 8), lshift(band(n, 0xFF), 8))
end

hton16 = bswap16
ntoh16 = hton16

_G.bswap = bswap -- export bit.bswap to global namespace to be consistent with bswap16
hton = bswap
ntoh = hton


local ffi = require "ffi"

ffi.cdef [[
	struct timeval {
		long tv_sec;
	        long tv_usec;
	};
	int gettimeofday(struct timeval* tv, void* tz);
]]

do
	local tv = ffi.new("struct timeval")
	
	function time()
		ffi.C.gettimeofday(tv, nil)
		return tonumber(tv.tv_sec) + tonumber(tv.tv_usec) / 10^6
	end
end


function checksum(data, len)
	data = ffi.cast("uint16_t*", data)
	local cs = 0
	for i = 0, len / 2 - 1 do
		cs = cs + data[i]
		if cs >= 2^16 then
			cs = band(cs, 0xFFFF) + 1
		end
	end
	return band(bnot(cs), 0xFFFF)
end

--- Parses a string to an IP address
-- @return address in ipv4_address OR ipv6_address format
function parseIPAddress(ip)
	local address = parseIP4Address(ip)
	if address == nil then
		address = parseIP6Address(ip)
	end
	return address	
end

--- Parses a string to an IPv4 address
-- @param address in string format
-- @return address in ipv4_address format
function parseIP4Address(ip)
	local bytes = {}
	bytes = {string.match(ip, '(%d+)%.(%d+)%.(%d+)%.(%d+)')}
	if bytes == nil then
		return
	end
	for i = 1, 4 do
		if bytes[i] == nil then
			return 
		end
		bytes[i] = tonumber(bytes[i])
		if  bytes[i] < 0 or bytes[i] > 255 then
			return
		end
	end
	
	-- build a uint32
	ip = bytes[1]
	for i = 2, 4 do
		ip = bor(lshift(ip, 8), bytes[i])
	
	end
	return  ip 
end

--- Parses a string to an IPv6 address
-- @param address in string format
-- @return address in ipv6_address format
function parseIP6Address(ip)
	-- TODO: better parsing (shortened addresses)
	local bytes = { ip:match('(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x):(%x%x)(%x%x)') }
	if #bytes ~= 16 then
		error("bad IPv6 format")
	end
	for i, v in ipairs(bytes) do
		bytes[i] = tonumber(bytes[i], 16)
	end
	
	-- build an ipv6_address by building four uint32s
	local addr = ffi.new("union ipv6_address")
	local uint32
	for i = 0, 3 do
		uint32 = bytes[1 + i * 4]
		for b = 2, 4 do
			uint32 = bor(lshift(uint32, 8), bytes[b + i * 4])
		end
		addr.uint32[3 - i] = uint32
	end
	return addr
end


