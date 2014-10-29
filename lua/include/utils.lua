
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


