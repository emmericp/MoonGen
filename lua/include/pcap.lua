--! @file pcap.lua
--! @brief Utility functions for PCAP file inport and export
--! pcap functionality was inspired by Snabb Switch's pcap functionality

local ffi = require("ffi")
local pkt = require("packet")

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
	pcapFile.version_major = 2.4
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
--! @param length: frame length -- TODO: aus buffer holen und hinter dem aufruf verstecken
function writeRecordHeader(file, length)
	--pcap record header
	local pcapRecord = ffi.new(pcaprec_hdr_s)
	pcapRecord.ts_sec, pcapRecord.ts_usec = 0, 0 --TODO sinnvolle funktion in util.lua 
	--TODO: meaningful pkt:getTimestamp() with usage of pkt:hasTimestamp()
	pcapRecord.incl_len = length
	pcapRecord.orig_len = length
	file:write(ffi.string(pcapRecord, ffi.sizeof(pcapRecord)))
end

--! Generate an iterator for pcap records.
--! @param file: the pcap file
--! @return: iterator for the pcap records
function readPcapRecords(file)  
	local pcapFile = readAs(file, pcap_hdr_s)
	if pcapFile.magic_number ~= 0xA1B2C3D4 then
		error("Bad PCAP magic number in " .. filename)
	end
	local function pcapRecordsIterator (t, i)
		local pcapRecordHdr = readAs(file, pcaprec_hdr_s)
		if pcapRecordHdr == nil then return nil end
		local packetData = file:read(math.min(pcapRecordHdr.orig_len, pcapRecordHdr.incl_len))
		return packetData, pcapRecordHdr
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
function pcapWriter:writePkt(buf)
	writeRecordHeader(self.file, buf:getSize())
	self.file:write(ffi.string(buf:getRawPacket(), buf:getSize()))
	self.file:flush()
end

pcapReader = {}

--! Generates a new pcapReader.
--! @param filename: filename to open and read from
function pcapReader:newPcapReader(filename)
	local file = io.open(filename, "r")
	 --TODO validy checks with more meaningfull errors in an extra function
	if file == nil then error("Cannot open pcap " .. filename) end
	local records = readPcapRecords(file)
	return setmetatable({iterator = records, done = false, file = file}, {__index = pcapReader})
end

function pcapReader:close()
	io.close(self.file)
end

--! Reads a record from the pcap
--! @param buf: a packet buffer
function pcapReader:readPkt(buf)
	--packetData, pcapRecordHdr
	local data, pcapRecord = self.iterator()
	local len = math.min(pcapRecord.orig_len, pcapRecord.incl_len)
	if data then
		buf:setRawPacket(data)
	else
		self.done = true
	end
end