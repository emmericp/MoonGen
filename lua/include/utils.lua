
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

--- Parse a string to a MAC address
-- @param mac address in string format
-- @return address in mac_address format or nil if invalid address
function parseMACAddress(mac)
	local bytes = {string.match(mac, '(%x+)[-:](%x+)[-:](%x+)[-:](%x+)[-:](%x+)[-:](%x+)')}
	if bytes == nil then
		return
	end
	for i = 1, 6 do
		if bytes[i] == nil then
			return 
		end
		bytes[i] = tonumber(bytes[i], 16)
		if  bytes[i] < 0 or bytes[i] > 0xFF then
			return
		end
	end
	
	addr = ffi.new("struct mac_address")
	for i = 0, 5 do
		addr.uint8[i] = bytes[i + 1]
	end
	return  addr 
end

--- Parse a string to an IP address
-- @return ip address in ipv4_address or ipv6_address format or nil if invalid address
function parseIPAddress(ip)
	local address = parseIP4Address(ip)
	if address == nil then
		address = parseIP6Address(ip)
	end
	return address	
end

--- Parse a string to an IPv4 address
-- @param ip address in string format
-- @return address in uint32 format or nil if invalid address
function parseIP4Address(ip)
	local bytes = {string.match(ip, '(%d+)%.(%d+)%.(%d+)%.(%d+)')}
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
	return ip
end

ffi.cdef[[
int inet_pton(int af, const char *src, void *dst);
]]

--- Parse a string to an IPv6 address
-- @param ip address in string format
-- @return address in ipv6_address format or nil if invalid address
function parseIP6Address(ip)
	local LINUX_AF_INET6 = 10 --preprocessor constant of Linux
	local tmp_addr = ffi.new("union ipv6_address")
	ffi.C.inet_pton(LINUX_AF_INET6, ip, tmp_addr)
	local addr = ffi.new("union ipv6_address")
	addr.uint32[0] = bswap(tmp_addr.uint32[3])
	addr.uint32[1] = bswap(tmp_addr.uint32[2])
	addr.uint32[2] = bswap(tmp_addr.uint32[1])
	addr.uint32[3] = bswap(tmp_addr.uint32[0])

	return addr
end


