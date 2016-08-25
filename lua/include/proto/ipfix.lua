------------------------------------------------------------------------
--- @file ipfix.lua
--- @brief IPFIX packet generation.
--- Utility functions for the ipfix_header structs
--- defined in \ref headers.lua . \n
--- Includes:
--- - IPFIX constants
--- - IPFIX header utility
--- - Definition of IPFIX packets
--- - Functions to create an IPFIX Message
------------------------------------------------------------------------

local ffi = require "ffi"
local pkt = require "packet"

require "utils"
require "headers"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bswap = bswap
local bswap16 = bswap16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift

---------------------------------------------------------------------------
---- IPFIX constants
---------------------------------------------------------------------------

--- IPFIX protocol constants
local ipfix = {}

-- NetFlow v5
ipfix.VERSION_NFV5 = 0x0005
-- NetFlow v9
ipfix.VERSION_NFV9 = 0x0009
-- IPFIX
ipfix.VERSION_IPFIX = 0x000a

-- Set ID for template set
ipfix.ID_TEMPLATE_SET = 0x0002
-- Set ID for option template set
ipfix.ID_OPTION_TEMPLATE_SET = 0x0003
-- Minimum data set ID
ipfix.ID_MIN_DATA_SET = 0x00ff
-- Enterprise bit
ipfix.ENTERPRISE_BIT = 0x00


---------------------------------------------------------------------------
---- IPFix header
---- https://tools.ietf.org/html/rfc7011#section-3.1
---------------------------------------------------------------------------

--- Module for ipfix struct (see \ref headers.lua).
local ipfixHeader = {}
ipfixHeader.__index = ipfixHeader

--- Set the version.
--- @param int version of the ipfix header as a 16 bits integer.
function ipfixHeader:setVersion(int)
	int = int or ipfix.VERSION_IPFIX
	self.version = hton16(int)
end

--- Retrieve the version.
--- @return version as a 16 bits integer.
function ipfixHeader:getVersion()
	return hton16(self.version)
end

--- Retrieve the version as string.
--- @return version as string.
function ipfixHeader:getVersionString()
	return self:getVersion()
end

--- Set the header length.
--- @param int length of the ipfix header as a 16 bits integer.
function ipfixHeader:setLength(int)
	int = int or 0
	self.length = hton16(int)
end

--- Retrieve the length.
--- @return length as a 16 bits integer.
function ipfixHeader:getLength()
	return hton16(self.length)
end

--- Retrieve the length as string.
--- @return length as string.
function ipfixHeader:getLengthString()
	return self:getLength()
end

--- Set the header export time.
--- @param int export time of the ipfix header as a 32 bits integer.
function ipfixHeader:setExportTime(int)
	int = int or 0
	self.export_time = bswap(int)
end

--- Retrieve the export time.
--- @return export time as a 32 bits integer.
function ipfixHeader:getExportTime()
	return bswap(self.export_time)
end

--- Retrieve the export time as string.
--- @return export time as string.
function ipfixHeader:getExportTimeString()
	return self:getExportTime()
end

--- Set the header seq.
--- @param int seq of the ipfix header as a 32 bits integer.
function ipfixHeader:setSeq(int)
	int = int or 0
	self.sequence_number = bswap(int)
end

--- Retrieve the seq.
--- @return seq as a 32 bits integer.
function ipfixHeader:getSeq()
	return bswap(self.sequence_number)
end

--- Retrieve the seq as string.
--- @return seq as string.
function ipfixHeader:getSeqString()
	return self:getSeq()
end

--- Set the header observation domain.
--- @param int observation domain id of the ipfix header as a 32 bits integer.
function ipfixHeader:setObservationDomain(int)
	int = int or 0
	self.observation_domain_id = bswap(int)
end

--- Retrieve the observation domain id.
--- @return obsevation domain as a 32 bits integer.
function ipfixHeader:getObservationDomain()
	return bswap(self.observation_domain_id)
end

--- Retrieve the observation domain as string.
--- @return observation domain as string.
function ipfixHeader:getObservationDomainString()
	return self:getObservationDomain()
end


--- Set all members of the ipfix header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: ipfixXYZ
--- @param pre prefix for namedArgs. Default 'ipfix'.
--- @code
--- fill() -- only default values
--- fill{ ipfixXYZ=1 } -- all members are set to default values with the exception of ipfixXYZ, ...
--- @endcode
function ipfixHeader:fill(args, pre)
	args = args or {}
	pre = pre or "ipfix"

	self:setVersion			(args[pre .. "Version"])
	self:setLength			(args[pre .. "Length"])
	self:setExportTime		(args[pre .. "ExportTime"])
	self:setSeq			(args[pre .. "Seq"])
	self:setObservationDomain	(args[pre .. "ObservationDomain"])
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'ipfix'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see ipfixHeader:fill
function ipfixHeader:get(pre)
	pre = pre or "ipfix"

	local args = {}
	args[pre .. "Version"]			= self:getVersion()
	args[pre .. "Length"]			= self:getLength()
	args[pre .. "ExportTime"]		= self:getExportTime()
	args[pre .. "Seq"]			= self:getSeq()
	args[pre .. "ObservationDomain"]	= self:getObservationDomain()

	return args
end

--- Retrieve the values of all members.
--- @return Values in string format.
function ipfixHeader:getString()
	return "ipfix > "
		.. " version "			.. self:getVersionString()
		.. " length "			.. self:getLengthString()
		.. " export time "		.. self:getExportTimeString()
		.. " sequence number "		.. self:getSeqString()
		.. " observation domain id "	.. self:getObservationDomainString()
end

--- Resolve which header comes after this one (in a packet)
--- For instance: in tcp/udp based on the ports
--- This function must exist and is only used when get/dump is executed on
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'eth', 'ip4', nil)
function ipfixHeader:resolveNextHeader()
	return nil
end	

--- Change the default values for namedArguments (for fill/get)
--- This can be used to for instance calculate a length value based on the total packet length
--- See ipfix/ip4.setDefaultNamedArgs as an example
--- This function must exist and is only used by packet.fill
--- @param pre The prefix used for the namedArgs, e.g. 'ipfix'
--- @param namedArgs Table of named arguments (see See more)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @see ipfixHeader:fill
function ipfixHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	if not namedArgs[pre .. "Length"] and namedArgs["pktLength"] then
		namedArgs[pre .. "Length"] = namedArgs["pktLength"] - accumulatedLength
	end

	return namedArgs
end


----------------------------------------------------------------------------------
---- Packets
----------------------------------------------------------------------------------

--[[ define how a packet with this header looks like
-- e.g. 'ip4' will add a member ip4 of type struct ip4_header to the packet
-- e.g. {'ip4', 'innerIP'} will add a member innerIP of type struct ip4_header to the packet
--]]
--- Cast the packet to a ipfix (IPFix) packet
pkt.getIpfixPacket = packetCreate("eth", "ip4", "udp", "ipfix")


----------------------------------------------------------------------------------
---- IPFix Message
----------------------------------------------------------------------------------

--- Creates an Information Element
--- @param id A numeric value that represents the Information Element
--- @param length The length of the corresponding encoded Information Element, in octets
--- @return a new Information Element
function ipfix:createInformationElement(id, length)
	local informationElement = InformationElement()
	informationElement.ie_id = hton16(id)
	informationElement.length = hton16(length)

	return informationElement
end

--- Creates a Set Header
--- @param id Set ID
--- @param length Total length of the Set, in octets, including the Set Header, records,
--- and the optional padding.
--- @return a new Set Header
function ipfix:createSetHeader(id, length)
	local setHeader = SetHeader()
	setHeader.set_id = hton16(id)
	setHeader.length = hton16(length)

	return setHeader
end

--- Creates a Template Record Header
--- @param id Template Id
--- @param fieldCount Number of fields in this Template Record
--- @return a new Template Record Header
function ipfix:createTmplRecordHeader(id, fieldCount)
	local tmplRecordHeader = TmplRecordHeader()
	tmplRecordHeader.template_id = hton16(id)
	tmplRecordHeader.field_count = hton16(fieldCount)

	return tmplRecordHeader
end

--- Creates an Options Template Record Header
--- @param id Options Template Id
--- @param fieldCount Number of fields in this Options Template Record
--- @param scopeFieldCount Number of scope fields in this Options Template Record
--- @return a new Options Template Record Header
function ipfix:createOptsTmplRecordHeader(id, fieldCount, scopeFieldCount)
	local optsTmplRecordHeader = OptsTmplRecordHeader()
	optsTmplRecordHeader.template_id = hton16(id)
	optsTmplRecordHeader.field_count = hton16(fieldCount)
	optsTmplRecordHeader.scope_field_count = hton16(scopeFieldCount)

	return optsTmplRecordHeader
end

--- Creates a Template Set with the Information Elements described in 'template'
--- @param id Template Set Id
--- @param template Contains the Information Elements for this Template Set, e.g.
--- @code
--- local template ={
--- {id = 8,  length = 4, value = function() return math.random(1207959553, 2432696319) end},
--- {id = 12, length = 4, value = function() return math.random(1207959553, 2432696319) end},
--- {id = 4,  length = 1, value = function() return 17 end},
--- {id = 7,  length = 2, value = function() return math.random(80, 100 end},
--- {id = 11, length = 2, value = function() return math.random(180, 200) end}
--- }
--- @endcode
--- id and length are defined in:
--- http://www.iana.org/assignments/ipfix/ipfix.xhtml#ipfix-information-elements
--- value is a function to calculate or return the the value to be used when creating a Data Record
--- @return a new Template Set
function ipfix:createTmplSet(id, template)
	local headerLength = ffi.sizeof(SetHeader)
	local recordHeaderLength = ffi.sizeof(TmplRecordHeader)
	local ieLength = ffi.sizeof(InformationElement)

	local set = TmplSet()
	local numOfFields = table.getn(template)
	local tmplSetLength = headerLength + recordHeaderLength + (ieLength * numOfFields)

	local header = self:createSetHeader(self.ID_TEMPLATE_SET, tmplSetLength)
	local record = TmplRecord()
	local recordHeader = self:createTmplRecordHeader(id, numOfFields)

	for i, ie in ipairs(template) do
		record.information_elements[i-1] = self:createInformationElement(ie.id, ie.length)
	end

	record.template_header = recordHeader
	set.set_header = header
	set.record = record

	return set
end


--- Creates an Options Template Set with the Information Elements described in 'opts_template'
--- @param id Options Template Set Id
--- @param opts_template Contains the Information Elements for this Options Template Set, e.g.
--- @code
--- local opts_template ={
--- {id = 8,  length = 4, value = function() return math.random(1207959553, 2432696319) end},
--- {id = 12, length = 4, value = function() return math.random(1207959553, 2432696319) end},
--- {id = 4,  length = 1, value = function() return 17 end},
--- {id = 7,  length = 2, value = function() return math.random(80, 100 end},
--- {id = 11, length = 2, value = function() return math.random(180, 200) end}
--- }
--- @endcode
--- id and length are defined in:
--- http://www.iana.org/assignments/ipfix/ipfix.xhtml#ipfix-information-elements
--- value is a function to calculate or return the the value to be used when creating a Data Record
--- @return a new Options Template Set
function ipfix:createOptsTmplSet(id, opts_template)
	local headerLength = ffi.sizeof(SetHeader)
	local recordHeaderLength = ffi.sizeof(OptsTmplRecordHeader)
	local ieLength = ffi.sizeof(InformationElement)

	local set = OptsTmplSet()
	local numOfFields = table.getn(opts_template)
	-- Add 2 more octets which correspond to the padding field
	local optsTmplSetLength = headerLength + recordHeaderLength + 2 + (ieLength * numOfFields)

	local header = self:createSetHeader(self.ID_OPTION_TEMPLATE_SET, optsTmplSetLength)
	local record = OptsTmplRecord()
	local recordHeader = self:createOptsTmplRecordHeader(id, numOfFields, 1)

	for i, ie in ipairs(opts_template) do
		record.information_elements[i-1] = self:createInformationElement(ie.id, ie.length)
	end

	record.template_header = recordHeader
	set.set_header = header
	set.record = record
	set.padding = hton16(0)

	return set
end

--- Calculates the length, in octets, of a Data Record based on its template
--- @param template Contains the Information Elements for this Flow Record
--- @return Flow Record's length, in octets
function ipfix:getRecordLength(template)
	local length = 0

	for _, ie in ipairs(template) do
		length = length + ie.length
	end

	return length
end

--- Creates a Data Set the Information Elements described in 'template'
--- @param id Template Id
--- @param template Contains the Information Elements for this Data Set
--- @param recordLength Length in octets for each Data Record
--- @param numOfRecords Number of Data Records within this Set
--- @return a new Data Set containing numOfRecords Data Records
function ipfix:createDataSet(id, template, recordLength, numOfRecords)
	local headerLength = ffi.sizeof(SetHeader)

	local header = self:createSetHeader(id, headerLength + (numOfRecords * recordLength))

	local set = DataSet(numOfRecords * recordLength)
	local index = 0

	for i = 1, numOfRecords do
		for _, ie in ipairs(template) do
			local offset = ie.length - 1

			while offset >= 0 do
				set.field_values[index] = bit.rshift(ie.value(), offset * 8)
				index = index + 1
				offset = offset - 1
			end
		end
	end

	set.set_header = header

	return set
end

--- Copies Set into destination
--- @param dest Destination for the set
--- @param pos Start position for this set in dest
--- @param set Set
--- @return End position for this set in destination
function ipfix:copyTo(dest, pos, set)
	local length = ntoh16(set.set_header.length)
	local s = ffi.string(set, length)
	local aux = 1

	length = length + pos

	while pos < length do
		dest[pos] = s:byte(aux)
		pos = pos + 1
		aux = aux + 1
	end

	return pos
end

--- Returns Header's length in octets
function ipfix:getHeadersLength()
	return ffi.sizeof(Header)
end


------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct ipfix_header", ipfixHeader)

-- ctypes
Header                = ffi.typeof("struct ipfix_header")
SetHeader             = ffi.typeof("struct ipfix_set_header")
InformationElement    = ffi.typeof("struct ipfix_information_element")
DataSet               = ffi.typeof("struct ipfix_data_set")
TmplSet               = ffi.typeof("struct ipfix_tmpl_set")
TmplRecord            = ffi.typeof("struct ipfix_tmpl_record")
TmplRecordHeader      = ffi.typeof("struct ipfix_tmpl_record_header")
OptsTmplSet           = ffi.typeof("struct ipfix_opts_tmpl_set")
OptsTmplRecord        = ffi.typeof("struct ipfix_opts_tmpl_record")
OptsTmplRecordHeader  = ffi.typeof("struct ipfix_opts_tmpl_record_header")

return ipfix
