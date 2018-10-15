--- The code originates from pudelkoMs FlowScope project, specifically this file: https://github.com/pudelkoM/FlowScope/blob/7beb980e2cb64284666ba2d62dda5727c7bfd499/lua/hmap.lua
--- This version has been slightly modified to work together with MoonGen/libmoon instead of FlowScope/flowtracker

local ffi = require "ffi"
local log = require "log"
local C = ffi.C

local hmapTemplate = [[
typedef struct hmapk{key_size}v{value_size} hmapk{key_size}v{value_size};
typedef struct hmapk{key_size}v{value_size}_accessor hmapk{key_size}v{value_size}_accessor;
hmapk{key_size}v{value_size}* hmapk{key_size}v{value_size}_create();
void hmapk{key_size}v{value_size}_delete(hmapk{key_size}v{value_size}* map);
void hmapk{key_size}v{value_size}_clear(hmapk{key_size}v{value_size}* map);
hmapk{key_size}v{value_size}_accessor* hmapk{key_size}v{value_size}_new_accessor();
void hmapk{key_size}v{value_size}_accessor_free(hmapk{key_size}v{value_size}_accessor* a);
void hmapk{key_size}v{value_size}_accessor_release(hmapk{key_size}v{value_size}_accessor* a);
bool hmapk{key_size}v{value_size}_access(hmapk{key_size}v{value_size}* map, hmapk{key_size}v{value_size}_accessor* a, const void* key);
bool hmapk{key_size}v{value_size}_find(hmapk{key_size}v{value_size}* map, hmapk{key_size}v{value_size}_accessor* a, const void* key);
bool hmapk{key_size}v{value_size}_erase(hmapk{key_size}v{value_size}* map, hmapk{key_size}v{value_size}_accessor* a);
uint8_t* hmapk{key_size}v{value_size}_accessor_get_value(hmapk{key_size}v{value_size}_accessor* a);
uint32_t hmapk{key_size}v{value_size}_clean(hmapk{key_size}v{value_size}* map, uint64_t threash);
]]

local module = {}

local keySizes = { 8, 16, 32, 64 }
local valueSizes = { 8, 16, 32, 64, 128 }

-- Get tbb hash map with fitting key and value size
function module.createHashmap(keySize, valueSize)
    local realKeySize, realValueSize = 0, 0
    if keySize <= 8 then
        realKeySize = 8
    elseif keySize <= 16 then
        realKeySize = 16
    elseif keySize <= 32 then
        realKeySize = 32
    elseif keySize <= 64 then
        realKeySize = 64
    else
        log:error("HashMap: Keys of size %d are not supported", keySize)
        return nil
    end
    if valueSize <= 8 then
        realValueSize = 8
    elseif valueSize <= 16 then
        realValueSize = 16
    elseif valueSize <= 32 then
        realValueSize = 32
    elseif valueSize <= 64 then
        realValueSize = 64
    elseif valueSize <= 128 then
        realValueSize = 128
    else
        log:error("HashMap: Values of size %d are not supported", valueSize)
        return nil
    end

    return C["hmapk" .. realKeySize .. "v" .. realValueSize .. "_create"]()
end

function makeHashmapFor(keySize, valueSize)
    local map = {}
    function map:clear()
        C["hmapk" .. keySize .. "v" .. valueSize .. "_clear"](self)
    end
    function map:delete()
        C["hmapk" .. keySize .. "v" .. valueSize .. "_delete"](self)
    end
    function map:access(a, tpl)
        return C["hmapk" .. keySize .. "v" .. valueSize .. "_access"](self, a, tpl)
    end
    function map:find(a, tpl)
        return C["hmapk" .. keySize .. "v" .. valueSize .. "_find"](self, a, tpl)
    end
    function map.newAccessor()
        return C["hmapk" .. keySize .. "v" .. valueSize .. "_new_accessor"]()
    end
    function map:erase(a)
        return C["hmapk" .. keySize .. "v" .. valueSize .. "_erase"](self, a)
    end
    function map.keyBufSize()
        return keySize
    end
    function map.valueSize()
        return valueSize
    end
    function map:clean(thresh)
        return C["hmapk" .. keySize .. "v" .. valueSize .. "_clean"](self, thresh)
    end
    local accessor = {}
    function accessor:get()
        return C["hmapk" .. keySize .. "v" .. valueSize .. "_accessor_get_value"](self)
    end
    function accessor:free()
        return C["hmapk" .. keySize .. "v" .. valueSize .. "_accessor_free"](self)
    end
    function accessor:release()
        return C["hmapk" .. keySize .. "v" .. valueSize .. "_accessor_release"](self)
    end
    map.__index = map
    accessor.__index = accessor
    ffi.metatype("hmapk" .. keySize .. "v" .. valueSize, map)
    ffi.metatype("hmapk" .. keySize .. "v" .. valueSize .. "_accessor", accessor)
end

for _, k in pairs(keySizes) do
    for _, v in pairs(valueSizes) do
        local definition, _ = hmapTemplate:gsub("{value_size}", v)
        definition, _ = definition:gsub("{key_size}", k)
        ffi.cdef(definition)
        makeHashmapFor(k, v)
    end
end

-- Helper function to get the size of the largest flow key
-- args is a table of hash maps
function module.getLargestKeyBufSize(args)
    local sz = {}
    for _, v in ipairs(args) do
        table.insert(sz, v.keyBufSize())
    end
    table.sort(sz)
    return sz[#sz]
end

return module
