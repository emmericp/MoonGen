---------------------------------
--- @file namespaces.lua
--- @brief Namespaces ...
--- @todo TODO docu
---------------------------------

local mod = {}

local ffi		= require "ffi"
local serpent	= require "Serpent"
local stp		= require "StackTracePlus"
local lock		= require "lock"
local log		= require "log"

ffi.cdef [[
	struct namespace { };
	struct namespace* create_or_get_namespace(const char* name);
	void namespace_store(struct namespace* ns, const char* key, const char* value);
	void namespace_delete(struct namespace* ns, const char* key);
	const char* namespace_retrieve(struct namespace* ns, const char* key);
	void namespace_iterate(struct namespace* ns, void (*func)(const char* key, const char* val));
	struct lock* namespace_get_lock(struct namespace* ns);
]]
local cbType = ffi.typeof("void (*)(const char* key, const char* val)")

local C = ffi.C

local namespace = {}
namespace.__index = namespace

local function getNameFromTrace()
	return debug.traceback():match("\n.-\n.-\n(.-)\n")
end

--- Get a namespace by its name creating it if necessary.
--- @param name the name, defaults to an auto-generated string consisting of the caller's filename and line number
function mod:get(name)
	name = name or getNameFromTrace()
	return C.create_or_get_namespace(name)
end

--- Retrieve a *copy* of a value in the namespace.
--- @param key the key, must be a string
function namespace:__index(key)
	if type(key) ~= "string" then
		log:fatal("Table index must be a string")
	end
	if key == "forEach" then
		return namespace.forEach
	elseif key == "lock" then
		return C.namespace_get_lock(self)
	end
	local val = C.namespace_retrieve(self, key)
	return val ~= nil and loadstring(ffi.string(val))() or nil
end

--- Store a value in the namespace.
--- @param key the key, must be a string
--- @param val the value to store, will be serialized
function namespace:__newindex(key, val)
	if type(key) ~= "string" then
		log:fatal("Table index must be a string")
	end
	if key == "forEach" or key == "lock" then
		log:fatal(key .. " is reserved", 2)
	end
	if val == nil then
		C.namespace_delete(self, key)
	else
		C.namespace_store(self, key, serpent.dump(val))
	end
end


--- Iterate over all keys/values in a namespace
--- Note: namespaces do not offer a 'normal' iterator (e.g. through a __pair metamethod) due to locking.
--- Iterating over a table requires a lock on the whole table; ensuring that the lock is released is
--- easier with a forEach method than with a regular iterator.
--- @param func function to call, receives (key, value) as arguments
function namespace:forEach(func)
	local caughtError
	local cb = ffi.cast(cbType, function(key, val)
		if caughtError then
			return
		end
		-- avoid throwing an error across the C++ frame unnecessarily
		-- not sure if this would work properly when compiled with clang instead of gcc
		local ok, err = xpcall(func, function(err)
			return stp.stacktrace(err)
		end, ffi.string(key), loadstring(ffi.string(val))())
		if not ok then
			caughtError = err
		end
	end)
	C.namespace_iterate(self, cb)
	cb:free()
	if caughtError then
		-- this is gonna be an ugly error message, but at least we get the full call stack
		log:fatal("Error while calling callback, inner error: " .. caughtError)
	end
end

ffi.metatype("struct namespace", namespace)

return mod

