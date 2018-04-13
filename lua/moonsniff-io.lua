--- Fast pcap IO, can write > 40 Gbit/s (to fs cache) and read > 30 Mpps (from fs cache).
--- Read/write performance can saturate several NVMe SSDs from a single core.

local mod = {}

local S      = require "syscall"
local ffi    = require "ffi"
local log    = require "log"
local libmoon = require "libmoon"

local cast = ffi.cast
local C = ffi.C


local INITIAL_FILE_SIZE = 512 * 1024 * 1024
local MSCAP_SIZE = 12 -- technically 16 bytes, but the last 4 are padding

--- Set the file size for new pcap writers
--- @param newSizeInBytes new file size in bytes
function mod:setInitialFilesize(newSizeInBytes)
    INITIAL_FILE_SIZE = newSizeInBytes
end

local writer = {}
writer.__index = writer

--- Create a new fast pcap writer with the given file name.
--- Call :close() on the writer when you are done.
--- @param startTime posix timestamp, all timestamps of inserted packets will be relative to this timestamp
---        default: relative to libmoon.getTime() == 0
function mod:newWriter(filename, startTime)
    startTime = startTime or wallTime() - libmoon.getTime()
    local fd = S.open(filename, "creat, rdwr, trunc", "0666")
    if not fd then
        log:fatal("could not create pcap file: %s", strError(S.errno()))
    end
    fd:nogc()
    local size = INITIAL_FILE_SIZE
    if not S.fallocate(fd, 0, 0, size) then
        log:fatal("fallocate failed: %s", strError(S.errno()))
    end
    local ptr = S.mmap(nil, size, "write", "shared, noreserve", fd, 0)
    if not ptr then
        log:fatal("mmap failed: %s", strError(S.errno()))
    end
    local offset = 0
    ptr = cast("uint8_t*", ptr)
    return setmetatable({fd = fd, ptr = ptr, size = size, offset = offset, startTime = startTime}, writer)
end

function writer:resize(size)
    if not S.fallocate(self.fd, 0, 0, size) then
        log:fatal("fallocate failed: %s", strError(S.errno()))
    end
    -- two ways to prevent MAP_MAYMOVE here if someone wants to implement this:
    -- 1) mmap a large virtual address block (and use MAP_FIXED to not have a huge file)
    -- 2) unmap the whole old area, mmap only the newly allocated file space (and the last page of the old space)
    -- problem with 1 is: wastes a lot of virtual address space, problematic if we have multiple writers at the same time
    -- so implement 2) if you feel like it (however, I haven't noticed big problems with the current MAP_MAYMOVE implementation)
    local ptr = S.mremap(self.ptr, self.size, size, "maymove")
    if not ptr then
        log:fatal("mremap failed: %s", strError(S.errno()))
    end
    self.ptr = cast("uint8_t*", ptr)
    self.size = size
end

--- Close and truncate the file.
function writer:close()
    S.munmap(self.ptr, self.size)
    S.ftruncate(self.fd, self.offset)
    S.fsync(self.fd)
    S.close(self.fd)
    self.fd = nil
    self.ptr = nil
end

ffi.cdef[[
	struct mscap {
                uint64_t timestamp;  /* timestamp in nanoseconds */
                uint32_t identification;   /* identifies a received packet */
        };

	void libmoon_write_mscap(void* dst, uint32_t identification, uint64_t timestamp);
]]

--- Write a packet to the pcap file
--- @param timestamp relative to the timestamp specified when creating the file
function writer:write(identification, timestamp)
    if self.offset + MSCAP_SIZE >= self.size then
        self:resize(self.size * 2)
    end
    C.libmoon_write_mscap(self.ptr + self.offset, identification, timestamp)
    self.offset = self.offset + MSCAP_SIZE
end

local reader = {}
reader.__index = reader

--- Create a new fast pcap reader for the given file name.
--- Call :close() on the reader when you are done to avoid fd leakage.
function mod:newReader(filename)
    local fd = S.open(filename, "rdonly")
    if not fd then
        log:fatal("could not open pcap file: %s", strError(S.errno()))
    end
    local size = fd:stat().size
    fd:nogc()
    local ptr = S.mmap(nil, size, "read", "private", fd, 0)
    if not ptr then
        log:fatal("mmap failed: %s", strError(S.errno()))
    end
    local offset = 0
    ptr = cast("uint8_t*", ptr)
    return setmetatable({fd = fd, ptr = ptr, size = size, offset = offset}, reader)
end

--- Read the next packet into a buf, the timestamp is stored in the udata64 field as microseconds.
--- The buffer's packet size corresponds to the original packet size, cut off bytes are zero-filled.
function reader:readSingle()
    local fileRemaining = self.size - self.offset
    if fileRemaining < MSCAP_SIZE then -- header size
        return nil
    end

    local mscap = cast(ffi.typeof("struct mscap*"), self.ptr + self.offset)
    self.offset = self.offset + MSCAP_SIZE
    return mscap
end

function reader:close()
    S.munmap(self.ptr, self.size)
    S.close(self.fd)
    self.fd = nil
    self.ptr = nil
end

function reader:reset()
    self.offset = ffi.sizeof(headerType)
end


return mod




