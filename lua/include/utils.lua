local bor, band, bnot, rshift, lshift, bswap = bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift, bit.bswap
local write = io.write
local format = string.format
local random, log, floor = math.random, math.log, math.floor

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

function map(t, f)
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

function toCsv(...)
	local vals = { tostringall(...) }
	for i, v in ipairs(vals) do
		if v:find("\"") then
			v = v:gsub("\"", "\"\"")
		end
		-- fields just containing \n or \r but not \n\r are not required to be quoted by RFC 4180...
		-- but I doubt that most parser could handle this ;)
		if v:find("\n") or v:find("\r") or v:find("\"") or v:find(",") then
			vals[i] = ("\"%s\""):format(v)
		end
	end
	return table.concat(vals, ",")
end

function printCsv(...)
	return print(toCsv(...))
end

--- Get the time to wait (in byte-times) for the next packet based on a poisson process.
-- @param average the average wait time between two packets
-- @returns the number of byte-times to wait to achieve the given average wait-time
function poissonDelay(average)
	return floor(-log(1 - random()) / (1 / average) + 0.5)
end

function rateToByteDelay(rate, size)
	size = size or 60
	return 10^10 / 8 / (rate * 10^6) - size - 24
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
function parseMacAddress(mac)
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
-- @return address ip address in ipv4_address or ipv6_address format or nil if invalid address
-- @return boolean true if IPv4 address, false otherwise
function parseIPAddress(ip)
	ip = tostring(ip)
	local address = parseIP4Address(ip)
	if address == nil then
		return parseIP6Address(ip), false
	end
	return address, true
end

--- Parse a string to an IPv4 address
-- @param ip address in string format
-- @return address in uint32 format or nil if invalid address
function parseIP4Address(ip)
	ip = tostring(ip)
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
	ip = tostring(ip)
	local LINUX_AF_INET6 = 10 --preprocessor constant of Linux
	local tmp_addr = ffi.new("union ipv6_address")
	local res = ffi.C.inet_pton(LINUX_AF_INET6, ip, tmp_addr)
	if res == 0 then
		return nil
	end

	local addr = ffi.new("union ipv6_address")
	addr.uint32[0] = bswap(tmp_addr.uint32[3])
	addr.uint32[1] = bswap(tmp_addr.uint32[2])
	addr.uint32[2] = bswap(tmp_addr.uint32[1])
	addr.uint32[3] = bswap(tmp_addr.uint32[0])

	return addr
end

--- Retrieve the system time with microseconds accuracy.
-- TODO use some C function to get microseconds.
-- @return System time in hh:mm:ss.uuuuuu format.
function getTimeMicros()
	local t = time()
	local h, m, s, u
	s = math.floor(t)	-- round to seconds
	u = t - s		-- micro seconds
	m = math.floor(s / 60)	-- total minutes
	s = s - m * 60		-- remaining seconds
	h = math.floor(m / 60)	-- total hours
	m = m - h * 60		-- remaining minutes
	h = h % 24		-- hour of the day
	s = s + u		-- seconds + micro seconds
	return format("%02d:%02d:%02.6f", h, m, s)
end

--- Print a hex dump of cdata.
-- @param data The cdata to be dumped.
-- @param bytes Number of bytes to dump.
function dumpHex(data, bytes)
	local data = ffi.cast("uint8_t*", data)
	for i = 0, bytes - 1 do
		if i % 16 == 0 then -- new line
			write(format("  0x%04x:   ", i))
		end

		write(format("%02x", data[i]))
		
		if i % 2  == 1 then -- group 2 bytes
			write(" ")
		end
		if i % 16 == 15 then -- end of 16 byte line
			write("\n")
		end
	end
	write("\n\n")
end

--- Print a hex dump of a packet.
-- @param data The cdata to be dumped.
-- @param bytes Number of bytes to dump.
-- @param args Arbitrary amount of protocol headers to be displayed in cleartext. The header must provide :getString().
function dumpPacket(data, bytes, ...)
	write(getTimeMicros())

	-- headers in cleartext
	for i = 1, select("#", ...) do
		local str = select(i, ...):getString()
		if i == 1 then write(" " .. str .. "\n") else print(str) end
	end

	-- hex dump
	dumpHex(data, bytes)
end

--- Merge tables.
-- @param args Arbitrary amount of tables to get merged.
function mergeTables(...)
	local table = {}
	if select("#", ...) > 0 then
		table = select(1, ...)
		for i = 2, select("#", ...) do
			for k,v in pairs(select(i, ...)) do
				table[k] = v
			end
		end
	end
	return table
end

--- Return all integerss in the range [start, max].
-- @param max upper bound
-- @param start lower bound, default = 1
function range(max, start, ...)
	start = start or 1
	if start > max then
		return ...
	end
	return start, range(max, start + 1, select(2, ...))
end


local unpackers = setmetatable({}, { __index = function(self, n)
	local func = loadstring(([[
		return function(tbl)
			return ]] .. ("tbl[%d], "):rep(n):sub(0, -3) .. [[
		end
	]]):format(range(n)))()
	rawset(self, n, func)
	return func
end })

--- unpack() with support for arrays with 'holes'.
function unpackAll(tbl)
	return unpackers[table.maxn(tbl)](tbl)
end

