---------------------------------
--- @file utils.lua
--- @brief Defines general utility functions.
--- @todo TODO docu
--- @todo local unpackers ... crashes lua2dox parser
---------------------------------
require "colors"

local bor, band, bnot, rshift, lshift, bswap = bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift, bit.bswap
local write = io.write
local format = string.format
local random, log, floor = math.random, math.log, math.floor
local ffi = require "ffi"

--- Print a formatted string.
--- @todo docu
--- @param str
--- @param args
--- @param return
function printf(str, ...)
	return print(str:format(...))
end

ffi.cdef[[
void print_ptr(void* ptr);
]]

--- Print a C pointer
-- @param ptr The pointer to print
function printPtr(ptr)
	ffi.Cprint_ptr(ptr)
end

--- Print a formatted error string.
--- @todo docu
--- @param str
--- @param args
function errorf(str, ...)
	error(str:format(...), 2)
end

--- TODO
--- @todo docu
--- @param f
--- @param args
--- @return
function mapVarArg(f, ...)
	local l = { ... }
	for i, v in ipairs(l) do
		l[i] = f(v)
	end
	return unpack(l)
end

--- TODO
--- @todo docu
--- @param t
--- @param f
--- @return
function map(t, f)
	for i, v in ipairs(t) do
		t[i] = f(v)
	end
	return t
end

--- TODO
--- @todo docu
--- @param args
--- @return
function tostringall(...)
	return mapVarArg(tostring, ...)
end

--- TODO
--- @todo docu
--- @param args
--- @return
function tonumberall(...)
	return mapVarArg(tonumber, ...)
end

--- TODO
--- @todo docu
--- @param args
--- @return
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

--- TODO
--- @todo docu
--- @param args
--- @return
function printCsv(...)
	return print(toCsv(...))
end

function trim(str)
	return str:match("^%s*(.-)%s*$")
end

--- Get the time to wait (in byte-times) for the next packet based on a poisson process.
--- @param average the average wait time between two packets
--- @returns the number of byte-times to wait to achieve the given average wait-time
function poissonDelay(average)
	return floor(-log(1 - random()) / (1 / average) + 0.5)
end

--- Convert a desired packet rate to the byte delay
--- @param rate The desired rate in Mbit per second
--- @param size The size of the (previous) packet
--- @return The byte delay
function rateToByteDelay(rate, size)
	size = size or 60
	return 10^10 / 8 / (rate * 10^6) - size - 24
end

--- Convert a desired inter-packet delay time to the byte delay
--- @param time The desired time in ns
--- @param rate The link rate in Mbit per second
--- @param size The size of the (previous) packet
--- @return
function timeToByteDelay(time, rate, size)
	rate = rate or 10000
	size = size or 60
	return time * 1.25 * (rate / 10^4) - size - 24
end


--- Byte swap for 16 bit integers
--- @param n 16 bit integer
--- @return Byte swapped integer
function bswap16(n)
	return bor(rshift(n, 8), lshift(band(n, 0xFF), 8))
end

hton16 = bswap16
ntoh16 = hton16

_G.bswap = bswap -- export bit.bswap to global namespace to be consistent with bswap16
hton = bswap
ntoh = hton

ffi.cdef [[
	typedef int clockid_t;
	struct timeval {
		long tv_sec;
	        long tv_usec;
	};
	struct timespec {
		long tv_sec;
		long tv_nsec;
	};

	int gettimeofday(struct timeval* tv, void* tz);
	int clock_gettime(clockid_t clk_id, struct timespec *tp);
]]

do
	local tv = ffi.new("struct timeval")

	function gettimeofday()
		ffi.C.gettimeofday(tv, nil)
		return tv.tv_sec, tv.tv_usec
	end
	
--- Return the current wall clock time
--- @return The time in seconds (as a double)
	function time()
		sec, usec = gettimeofday()
		return tonumber(sec + usec / 10^6)
	end

	local ts = ffi.new("struct timespec")

--- Return the current monotonic clock time
--- @return The time in seconds (as a double)
	function getMonotonicTime()
		-- CLOCK_MONOTONIC = 1
		ffi.C.clock_gettime(1, ts)
		return ts.tv_sec + ts.tv_nsec / 10^9
	end
end

--- Subtract timeval values
--- @param x the "later" timeval (Minuend)
--- @param y the "earlier" time (Subtrahend)
--- @return The result in microseconds
function timevalSpan(x, y)
	return (x.tv_sec - y.tv_sec) * 1000000 + (x.tv_usec - y.tv_usec)
end


--- Calculate a 16 bit checksum 
--- @param data cdata to calculate the checksum for.
--- @param len Number of bytes to calculate the checksum for.
--- @return 16 bit integer
function checksum(data, len)
	data = ffi.cast("uint16_t*", data)
	local cs = 0
	for i = 0, len / 2 - 1 do
		cs = cs + data[i]
		if cs >= 2^16 then
			cs = band(cs, 0xFFFF) + 1
		end
	end
	-- missing the very last uint_8 for odd sized packets
	-- note that this access is always valid in MoonGen
	--  * buffers are a fixed even size >= pkt len
	--  * pkt length is just metadata and not the actual length of the buffer
	if (len % 2) == 1 then
		-- simply null the byte outside of our packet
		cs = cs + band(data[len / 2], 0xFF)
		if cs >= 2^16 then
			cs = band(cs, 0xFFFF) + 1
		end
	end
	return band(bnot(cs), 0xFFFF)
end

--- Parse a string to a MAC address
--- @param mac address in string format
--  @param number return as number
--- @return address in mac_address format or nil if invalid address
function parseMacAddress(mac, number)
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
	
	if number then
		local acc = 0
		for i = 1, 6 do
			acc = acc + bytes[i] * 256 ^ (i - 1)
		end
		return acc
	else
		addr = ffi.new("union mac_address")
		for i = 0, 5 do
			addr.uint8[i] = bytes[i + 1]
		end
		return addr 
	end
end

--- Parse a string to an IP address
--- @return address ip address in ip4_address or ip6_address format or nil if invalid address
--- @return boolean true if IPv4 address, false otherwise
function parseIPAddress(ip)
	ip = tostring(ip)
	local address = parseIP4Address(ip)
	if address == nil then
		return parseIP6Address(ip), false
	end
	return address, true
end

--- Parse a string to an IPv4 address
--- @param ip address in string format
--- @return address in uint32 format or nil if invalid address
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
--- @param ip address in string format
--- @return address in ip6_address format or nil if invalid address
function parseIP6Address(ip)
	ip = tostring(ip)
	local LINUX_AF_INET6 = 10 --preprocessor constant of Linux
	local tmp_addr = ffi.new("union ip6_address")
	local res = ffi.C.inet_pton(LINUX_AF_INET6, ip, tmp_addr)
	if res == 0 then
		return nil
	end

	local addr = ffi.new("union ip6_address")
	addr.uint32[0] = bswap(tmp_addr.uint32[3])
	addr.uint32[1] = bswap(tmp_addr.uint32[2])
	addr.uint32[2] = bswap(tmp_addr.uint32[1])
	addr.uint32[3] = bswap(tmp_addr.uint32[0])

	return addr
end

--- Retrieve the system time with microseconds accuracy.
--- @todo use some C function to get microseconds.
--- @return System time in hh:mm:ss.uuuuuu format.
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
--- @param data The cdata to be dumped.
--- @param bytes Number of bytes to dump.
--- @param stream the stream to write to, defaults to io.stdout
function dumpHex(data, bytes, stream)
	local data = ffi.cast("uint8_t*", data)
	stream = stream or io.stdout
	for i = 0, bytes - 1 do
		if i % 16 == 0 then -- new line
			stream:write(format("  0x%04x:   ", i))
		end

		stream:write(format("%02x", data[i]))
		
		if i % 2  == 1 then -- group 2 bytes
			stream:write(" ")
		end
		if i % 16 == 15 then -- end of 16 byte line
			stream:write("\n")
		end
	end
	stream:write("\n\n")
end

--- Merge tables.
--- @param args Arbitrary amount of tables to get merged.
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
--- @param max upper bound
--- @param start lower bound, default = 1
function range(max, start, ...)
	start = start or 1
	if start > max then
		return ...
	end
	return start, range(max, start + 1, select(2, ...))
end

local band = bit.band
local sar = bit.arshift

--- Increment a wrapping counter, i.e. (val + 1) % max
--- This function is optimized to generate branchless code and faster than a naive modulo-based implementation.
--- @note: all attempts to wrap this in a nice and simple class have failed (~30% performance impact).
--- @param val Current value (number)
--- @param max Maximum allowed value of val (number)
--- @return Incremented and wrapped number
function incAndWrap(val, max)
	return band(val + 1, sar(val - max + 1, 31))
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
--- @param tbl Table to unpack
--- @return Unpacked values
function unpackAll(tbl)
	return unpackers[table.maxn(tbl)](tbl)
end

function run(cmd)
	local file = io.popen(cmd, "r")
	if not file then
		return false
	end
	local s = assert(file:read('*a'))
	file:close()
	return s
end

--- Get the operation system type and version
-- @return osName, major, minor, patch
function getOS()
	local os = run("uname")
	if not os then
		return nil
	end
	local ver = run("uname -r")
	if not ver then
		return os, 0, 0, 0
	end
	local major, minor, patch = tonumberall(ver:match("(%d+)%.(%d+)%.(%d+)"))
	return trim(os), major, minor, patch
end


