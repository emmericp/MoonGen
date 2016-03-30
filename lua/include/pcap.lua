--! @file pcap.lua
--! @brief Utility functions for PCAP file inport and export
--! pcap functionality was inspired by Snabb Switch's pcap functionality

local ffi = require("ffi")
local pkt = require("packet")
local mg  = require("dpdk")

require("utils")
require("headers")

-- http://wiki.wireshark.org/Development/LibpcapFileFormat/
local pcap_hdr_s = ffi.typeof[[
struct {
	unsigned int magic_number;    /* magic number */
	unsigned short version_major; /* major version number */
	unsigned short version_minor; /* minor version number */
	int  thiszone;                /* GMT to local correction */
	unsigned int sigfigs;         /* accuracy of timestamps */
	unsigned int snaplen;         /* max length of captured packets, in octets */
	unsigned int network;         /* data link type */
}
]]

local pcaprec_hdr_s = ffi.typeof[[
struct {
	unsigned int ts_sec;         /* timestamp seconds */
	unsigned int ts_usec;        /* timestamp microseconds */
	unsigned int incl_len;       /* number of octets of packet saved in file */
	unsigned int orig_len;       /* actual length of packet */
}
]]

--! Writes pcap file header.
--! @param file: the file
function writePcapFileHeader(file)
	local pcapFile = ffi.new(pcap_hdr_s)
	--magic_number: used to detect the file format itself and the byte ordering. The writing application writes 0xa1b2c3d4 with it's native byte ordering format into this field. The reading application will read either 0xa1b2c3d4 (identical) or 0xd4c3b2a1 (swapped). If the reading application reads the swapped 0xd4c3b2a1 value, it knows that all the following fields will have to be swapped too. For nanosecond-resolution files, the writing application writes 0xa1b23c4d, with the two nibbles of the two lower-order bytes swapped, and the reading application will read either 0xa1b23c4d (identical) or 0x4d3cb2a1 (swapped). 
	pcapFile.magic_number = 0xa1b2c3d4
	pcapFile.version_major = 2
	pcapFile.version_minor = 4 
	pcapFile.thiszone = 0 --TODO function for time zones in utils.lua
	--snaplen: the "snapshot length" for the capture (typically 65535 or even more, but might be limited by the user), see: incl_len vs. orig_len below 
	pcapFile.snaplen = 65535
	pcapFile.network = 1 -- 1 for Ethernet
	file:write(ffi.string(pcapFile, ffi.sizeof(pcapFile)))
	file:flush()
end

--! Writes a pcap record header.
--! @param file: the file to write to
--! @param buf: the packet buffer
--! @param ts: the timestamp of the packet in seconds
function writeRecordHeader(file, buf, ts)
	--pcap record header
	local pcapRecord = ffi.new(pcaprec_hdr_s)
	if ts then
		pcapRecord.ts_sec, pcapRecord.ts_usec = math.floor(ts), (ts - math.floor(ts)) * 10^6
	else
		pcapRecord.ts_sec, pcapRecord.ts_usec = 0,0
	end
	pcapRecord.incl_len = buf:getSize()
	pcapRecord.orig_len = buf:getSize()
	file:write(ffi.string(pcapRecord, ffi.sizeof(pcapRecord)))
end

--! Generate an iterator for pcap records.
--! @param file: the pcap file
--! @param rate: the tx link rate in Mbit per second if packets should have proper delays
--! @return: iterator for the pcap records
function readPcapRecords(file, rate)  
	local pcapFile = readAs(file, pcap_hdr_s)
	local pcapNSResolution = false
	if pcapFile.magic_number == 0xA1B2C34D then
		pcapNSResolution = true
	elseif pcapFile.magic_number ~= 0xA1B2C3D4 then
		error("Bad PCAP magic number in " .. filename)
	end
	local lastRecordHdr = nil
	local function pcapRecordsIterator (t, i)
		local pcapRecordHdr = readAs(file, pcaprec_hdr_s)
		if pcapRecordHdr == nil then return nil end
		local packetData = file:read(math.min(pcapRecordHdr.orig_len, pcapRecordHdr.incl_len))
		local delay = 0
		if lastRecordHdr and rate then
			local diff = timevalSpan(
					{ tv_sec = pcapRecordHdr.ts_sec, tv_usec = pcapRecordHdr.ts_usec },
					{ tv_sec = lastRecordHdr.ts_sec, tv_usec = lastRecordHdr.ts_usec }
				)
			if not pcapNSResolution then diff = diff * 10^3 end --convert us to ns
			delay = timeToByteDelay(diff, rate, lastRecordHdr.orig_len)
		end
		lastRecordHdr = pcapRecordHdr
		return packetData, pcapRecordHdr, delay
	end
	return pcapRecordsIterator, true, true
end

--! Read a C object of <type> from <file>
--! @param file: tje pcap file
--! @param fileType: the type that the file data should be casted to
function readAs(file, fileType)
	local str = file:read(ffi.sizeof(fileType))
	if str == nil then 
		return nil 
	end
	if #str ~= ffi.sizeof(fileType) then
		error("type read error " .. fileType .. ", \"" .. tostring(file) .. "\" is to short ")
	end
   local obj = ffi.new(fileType)
   ffi.copy(obj, str, ffi.sizeof(fileType))
   return obj
end

pcapWriter = {}

--! Generates a new pcapWriter.
--! @param filename: filename to open and write to
function pcapWriter:newPcapWriter(filename)
	local file = io.open(filename, "w")
	writePcapFileHeader(file)
	return setmetatable({file = file}, {__index = pcapWriter})
end

function pcapWriter:close()
	io.close(self.file)
end

--! Writes a packet to the pcap.
--! @param buf: packet buffer
--! @param ts optional: a timestamp in seconds (as double)
function pcapWriter:writePkt(buf, ts)
	if ts and not not self.starttime then
		self.starttime = ts
		print("starttime", self.starttime)
	end
	writeRecordHeader(self.file, buf, ts and ts - self.starttime or 0)
	self.file:write(ffi.string(buf:getRawPacket(), buf:getSize()))
	self.file:flush()
end

--! Writes a packet to the pcap.
--! @param buf: packet buffer
--! @param ts: timestamp from CPU TSC register
function pcapWriter:writePktTSC(buf, ts)
	if not self.starttime then
		self.tscFreq = mg.getCyclesFrequency()
		self.starttime = ts
		print("starttime", self.starttime)
	end
	local tscDelta = tonumber(ts - self.starttime)
	local realTS = tscDelta / self.tscFreq
	writeRecordHeader(self.file, buf, realTS)
	self.file:write(ffi.string(buf:getRawPacket(), buf:getSize()))
	self.file:flush()
end

pcapReader = {}

--! Generates a new pcapReader.
--! @param filename: filename to open and read from
--! @param rate: The rate of the link, if the packets are supposed to be replayed
function pcapReader:newPcapReader(filename, rate)
	rate = rate or 10000
	local file = io.open(filename, "r")
	 --TODO validity checks with more meaningful errors in an extra function
	if file == nil then error("Cannot open pcap " .. filename) end
	local records = readPcapRecords(file, rate)
	return setmetatable({iterator = records, done = false, file = file}, {__index = pcapReader})
end

function pcapReader:close()
	io.close(self.file)
end

--! Reads a record from the pcap
--! @param buf: a packet buffer
function pcapReader:readPkt(buf, withDelay)
	withDelay = withDelay or false
	local data, pcapRecord, delay = self.iterator()
	if data then
		buf:setRawPacket(data)
		if withDelay then
			buf:setDelay(delay)
		end
	else
		self.done = true
	end
end
