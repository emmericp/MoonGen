local mod = {}

local dpdkc	= require "dpdkc"
local dpdk	= require "dpdk"
local ffi	= require "ffi"

-- Intel X540 registers
local SECTXCTRL		= 0x00008800
local SECRXCTRL		= 0x00008D00
local SECTXSTAT		= 0x00008804
local SECRXSTAT		= 0x00008D04
local SECTXMINIFG	= 0x00008810
local SECTXBUFFAF	= 0x00008808

local IPSTXIDX		= 0x00008900
local IPSTXKEY_3	= 0x00008914 --MSB of key
local IPSTXKEY_2	= 0x00008910
local IPSTXKEY_1	= 0x0000890C
local IPSTXKEY_0	= 0x00008908 --LSB of key
local IPSTXSALT		= 0x00008904

local IPSRXIDX		= 0x00008E00
local IPSRXKEY_3	= 0x00008E28 --MSB of key
local IPSRXKEY_2	= 0x00008E24
local IPSRXKEY_1	= 0x00008E20
local IPSRXKEY_0	= 0x00008E1C --LSB ofkey
local IPSRXSALT		= 0x00008E2C
local IPSRXMOD		= 0x00008E30

--Note: Field is defined in Big Endian (LS byte is first on the wire).
local IPSRXIPADDR_3	= 0x00008E10 --LSB of IPv6 or IPv4
local IPSRXIPADDR_2	= 0x00008E0C
local IPSRXIPADDR_1	= 0x00008E08
local IPSRXIPADDR_0	= 0x00008E04 --MSB of IPv6 or 0

--Note: Field is defined in Big Endian (LS byte is first on the wire).
local IPSRXSPI		= 0x00008E14
local IPSRXIPIDX	= 0x00008E18

-- Helper function to return padded, unsigned 32bit hex string.
function uhex32(x)
	return bit.tohex(x, 8)
end

-- Helper function to clear a single bit
function clear_bit32(reg32, idx)
	if idx < 0 or idx > 31 then
		error("Idx must be in range 0-31")
	end
	local mask = bit.bnot(bit.lshift(0x1, idx))
	return bit.band(reg32, mask)
end

-- Helper function to set a single bit
function set_bit32(reg32, idx)
	if idx < 0 or idx > 31 then
		error("Idx must be in range 0-31")
	end
	return bit.bor(reg32, bit.lshift(0x1, idx))
end

-- Helper function to clear the bits (MSB) from..to (LSB)
function clear_bits32(reg32, from, to)
	local tmp = reg32
	for i=from,to,-1 do
		tmp = clear_bit32(tmp, i)
	end
	return tmp
end

-- Helper function to set the bits (MSB) from..to (LSB)
function set_bits32(reg32, from, to, value)
	local upper_limit = math.pow(2, ((from-to)+1))-1 --i.e. (2^num_bits)-1
	if value < 0 or value > upper_limit then
		error("Value must be in range 0-"..upper_limit)
	end
	local tmp = clear_bits32(reg32, from, to)
	return bit.bor(tmp, bit.lshift(value, to))
end

function dump_regs(port)
	print("===== DUMP REGS =====")
	local reg = dpdkc.read_reg32(port, SECTXCTRL)
	print("SECTXCTRL: 0x"..uhex32(reg))
	local reg = dpdkc.read_reg32(port, SECRXCTRL)
	print("SECRXCTRL: 0x"..uhex32(reg))
	local reg = dpdkc.read_reg32(port, SECTXSTAT)
	print("SECTXSTAT: 0x"..uhex32(reg))
	local reg = dpdkc.read_reg32(port, SECRXSTAT)
	print("SECRXSTAT: 0x"..uhex32(reg))
	local reg = dpdkc.read_reg32(port, SECTXMINIFG)
	print("SECTXMINIFG: 0x"..uhex32(reg))
	local reg = dpdkc.read_reg32(port, SECTXBUFFAF)
	print("SECTXBUFFAF: 0x"..uhex32(reg))
end

function mod.enable(port)
	print("IPsec enable, port: "..port)
	dump_regs(port)

	-- Stop TX data path (set TX_DIS bit)
	local SECTXCTRL__VALUE = set_bit32(dpdkc.read_reg32(port, SECTXCTRL), 1) --set TX_DIS
	dpdkc.write_reg32(port, SECTXCTRL, SECTXCTRL__VALUE)

	-- Stop RX data path (set RX_DIS bit)
	local SECRXCTRL__VALUE = set_bit32(dpdkc.read_reg32(port, SECRXCTRL), 1) --set RX_DIS
	dpdkc.write_reg32(port, SECRXCTRL, SECRXCTRL__VALUE)

	-- Wait for the data paths to be emptied by hardware (check SECTX/RX_RDY bits).
	repeat
		print("Waiting for registers to be asserted by hardware...")
		dpdk.sleepMillis(100) -- wait 100ms before poll
		local SECTXSTAT__SECTX_RDY = bit.band(dpdkc.read_reg32(port, SECTXSTAT), 0x1)
		local SECRXSTAT__SECRX_RDY = bit.band(dpdkc.read_reg32(port, SECRXSTAT), 0x1)
		print("SECTX_RDY: "..SECTXSTAT__SECTX_RDY..", SECRX_RDY: "..SECRXSTAT__SECRX_RDY)
	until SECTXSTAT__SECTX_RDY == 0x1 and SECRXSTAT__SECRX_RDY == 0x1

	-- Set MINSECIFG to 0x3
	local SECTXMINIFG__VALUE = set_bits32(dpdkc.read_reg32(port, SECTXMINIFG), 3, 0, 0x3) --set MINSECIFG
	dpdkc.write_reg32(port, SECTXMINIFG, SECTXMINIFG__VALUE)

	-- Set FULLTHRESH to 0x15
	local SECTXBUFFAF__VALUE = set_bits32(dpdkc.read_reg32(port, SECTXBUFFAF), 9, 0, 0x15) --set FULLTHRESH
	dpdkc.write_reg32(port, SECTXBUFFAF, SECTXBUFFAF__VALUE)

	-- Enable TX crypto engine
	local SECTXCTRL__VALUE = clear_bit32(dpdkc.read_reg32(port, SECTXCTRL), 0) --clear SECTX_DIS
	SECTXCTRL__VALUE = set_bit32(SECTXCTRL__VALUE, 2) --set STORE_FORWARD
	dpdkc.write_reg32(port, SECTXCTRL, SECTXCTRL__VALUE)

	-- Enable RX crypto engine
	local SECRXCTRL__VALUE = clear_bit32(dpdkc.read_reg32(port, SECRXCTRL), 0) --clear SECRX_DIS
	dpdkc.write_reg32(port, SECRXCTRL, SECRXCTRL__VALUE)

	-- Enable IPsec TX SA lookup
	local IPSTXIDX__VALUE = set_bit32(dpdkc.read_reg32(port, IPSTXIDX), 0) --set IPS_TX_EN
	dpdkc.write_reg32(port, IPSTXIDX, IPSTXIDX__VALUE)

	-- Enable IPsec RX SA lookup
	local IPSRXIDX__VALUE = set_bit32(dpdkc.read_reg32(port, IPSRXIDX), 0) --set IPS_RX_EN
	dpdkc.write_reg32(port, IPSRXIDX, IPSRXIDX__VALUE)

	-- Restart TX data path (clear TX_DIS bit)
	local SECTXCTRL__VALUE = clear_bit32(dpdkc.read_reg32(port, SECTXCTRL), 1) --clear TX_DIS
	dpdkc.write_reg32(port, SECTXCTRL, SECTXCTRL__VALUE)

	-- Restart RX data path (clear RX_DIS bit)
	local SECRXCTRL__VALUE = clear_bit32(dpdkc.read_reg32(port, SECRXCTRL), 1) --clear RX_DIS
	dpdkc.write_reg32(port, SECRXCTRL, SECRXCTRL__VALUE)

	dump_regs(port)
end

function mod.disable(port)
	print("IPsec disable, port: "..port)
	dump_regs(port)

	-- Stop TX data path (set TX_DIS bit)
	local SECTXCTRL__VALUE = set_bit32(dpdkc.read_reg32(port, SECTXCTRL), 1) --set TX_DIS
	dpdkc.write_reg32(port, SECTXCTRL, SECTXCTRL__VALUE)

	-- Stop RX data path (set RX_DIS bit)
	local SECRXCTRL__VALUE = set_bit32(dpdkc.read_reg32(port, SECRXCTRL), 1) --set RX_DIS
	dpdkc.write_reg32(port, SECRXCTRL, SECRXCTRL__VALUE)

	-- Wait for the data paths to be emptied by hardware (check SECTX/RX_RDY bits).
	repeat
		print("Waiting for registers to be asserted by hardware...")
		dpdk.sleepMillis(100) -- wait 100ms before poll
		local SECTXSTAT__SECTX_RDY = bit.band(dpdkc.read_reg32(port, SECTXSTAT), 0x1)
		local SECRXSTAT__SECRX_RDY = bit.band(dpdkc.read_reg32(port, SECRXSTAT), 0x1)
		print("SECTX_RDY: "..SECTXSTAT__SECTX_RDY..", SECRX_RDY: "..SECRXSTAT__SECRX_RDY)
	until SECTXSTAT__SECTX_RDY == 0x1 and SECRXSTAT__SECRX_RDY == 0x1

	-- Disable IPsec TX SA lookup
	local IPSTXIDX__VALUE = clear_bit32(dpdkc.read_reg32(port, IPSTXIDX), 0) --clear IPS_TX_EN
	dpdkc.write_reg32(port, IPSTXIDX, IPSTXIDX__VALUE)

	-- Disable IPsec RX SA lookup
	local IPSRXIDX__VALUE = clear_bit32(dpdkc.read_reg32(port, IPSRXIDX), 0) --clear IPS_RX_EN
	dpdkc.write_reg32(port, IPSRXIDX, IPSRXIDX__VALUE)

	--TODO: what about MINSECIFG?

	-- Set FULLTHRESH to 0x250
	local SECTXBUFFAF__VALUE = set_bits32(dpdkc.read_reg32(port, SECTXBUFFAF), 9, 0, 0x250) --set FULLTHRESH
	dpdkc.write_reg32(port, SECTXBUFFAF, SECTXBUFFAF__VALUE)

	-- Disable TX crypto engine
	local SECTXCTRL__VALUE = set_bit32(dpdkc.read_reg32(port, SECTXCTRL), 0) --set SECTX_DIS
	SECTXCTRL__VALUE = clear_bit32(SECTXCTRL__VALUE, 2) --clear STORE_FORWARD
	dpdkc.write_reg32(port, SECTXCTRL, SECTXCTRL__VALUE)

	-- Disable RX crypto engine
	local SECRXCTRL__VALUE = set_bit32(dpdkc.read_reg32(port, SECRXCTRL), 0) --set SECRX_DIS
	dpdkc.write_reg32(port, SECRXCTRL, SECRXCTRL__VALUE)

	-- Restart TX data path (clear TX_DIS bit)
	local SECTXCTRL__VALUE = clear_bit32(dpdkc.read_reg32(port, SECTXCTRL), 1) --clear TX_DIS
	dpdkc.write_reg32(port, SECTXCTRL, SECTXCTRL__VALUE)

	-- Restart RX data path (clear RX_DIS bit)
	local SECRXCTRL__VALUE = clear_bit32(dpdkc.read_reg32(port, SECRXCTRL), 1) --clear RX_DIS
	dpdkc.write_reg32(port, SECRXCTRL, SECRXCTRL__VALUE)

	dump_regs(port)
end

-- Write AES 128 bit SA into hw SA TX table
-- @idx: Index into SA TX table (0-1023)
-- @key: 128 bit AES key  (as hex string)
-- @salt: 32 bit AES salt (as hex string)
function mod.tx_set_key(port, idx, key, salt)
	if idx > 1023 or idx < 0 then
		error("Idx must be in range 0-1023")
	end
	if string.len(key) ~= 32 then
		error("Key must be 128 bit (hex string).")
	end
	if string.len(salt) ~= 8 then
		error("Salt must be 32 bit (hex string).")
	end

	local key_3 = tonumber(string.sub(key,  1,  8), 16) --MSB
	local key_2 = tonumber(string.sub(key,  9, 16), 16)
	local key_1 = tonumber(string.sub(key, 17, 24), 16)
	local key_0 = tonumber(string.sub(key, 25, 32), 16) --LSB
	local _salt = tonumber(salt, 16)

	local IPSTXIDX__BASE		= clear_bits32(dpdkc.read_reg32(port, IPSTXIDX), 12, 3) --clear SA_IDX
	local IPSTXIDX__SA_IDX		= bit.lshift(idx, 3)
	local IPSTXIDX__READ		= bit.lshift(0, 30)
	local IPSTXIDX__WRITE		= bit.lshift(1, 31)
	local IPSTXIDX__VALUE = bit.bor(
		IPSTXIDX__BASE,
		IPSTXIDX__SA_IDX,
		IPSTXIDX__READ,
		IPSTXIDX__WRITE)
	--print("IPSTXIDX__VALUE: 0x"..uhex32(IPSTXIDX__VALUE))

	--prepare registers
	dpdkc.write_reg32(port, IPSTXKEY_3, key_3)
	dpdkc.write_reg32(port, IPSTXKEY_2, key_2)
	dpdkc.write_reg32(port, IPSTXKEY_1, key_1)
	dpdkc.write_reg32(port, IPSTXKEY_0, key_0)
	dpdkc.write_reg32(port, IPSTXSALT, _salt)
	--push to hw
	dpdkc.write_reg32(port, IPSTXIDX, IPSTXIDX__VALUE)
	--pass SA_IDX via 'TX context descriptor' to use this SA!
end

function mod.tx_get_key(port, idx)
	if idx > 1023 or idx < 0 then
		error("Idx must be in range 0-1023")
	end

	local IPSTXIDX__BASE		= clear_bits32(dpdkc.read_reg32(port, IPSTXIDX), 12, 3) --clear SA_IDX
	local IPSTXIDX__SA_IDX		= bit.lshift(idx, 3)
	local IPSTXIDX__READ		= bit.lshift(1, 30)
	local IPSTXIDX__WRITE		= bit.lshift(0, 31)
	local IPSTXIDX__VALUE = bit.bor(
		IPSTXIDX__BASE,
		IPSTXIDX__SA_IDX,
		IPSTXIDX__READ,
		IPSTXIDX__WRITE)
	--print("IPSTXIDX__VALUE: 0x"..uhex32(IPSTXIDX__VALUE))

	--pull from hw
	dpdkc.write_reg32(port, IPSTXIDX, IPSTXIDX__VALUE)

	--fetch result
	local key_3 = dpdkc.read_reg32(port, IPSTXKEY_3)
	local key_2 = dpdkc.read_reg32(port, IPSTXKEY_2)
	local key_1 = dpdkc.read_reg32(port, IPSTXKEY_1)
	local key_0 = dpdkc.read_reg32(port, IPSTXKEY_0)
	local _salt  = dpdkc.read_reg32(port, IPSTXSALT)

	local key = uhex32(key_3)..uhex32(key_2)..uhex32(key_1)..uhex32(key_0)

	return key, uhex32(_salt)
end

-- Write AES 128 bit SA into hw SA RX table
-- @idx: Index into SA RX table (0-1023)
-- @key: 128 bit AES key  (as hex string)
-- @salt: 32 bit AES salt (as hex string)
function mod.rx_set_key(port, idx, key, salt)
	if idx > 1023 or idx < 0 then
		error("Idx must be in range 0-1023")
	end
	if string.len(key) ~= 32 then
		error("Key must be 128 bit (hex string).")
	end
	if string.len(salt) ~= 8 then
		error("Salt must be 32 bit (hex string).")
	end

	local key_3 = tonumber(string.sub(key,  1,  8), 16) --MSB
	local key_2 = tonumber(string.sub(key,  9, 16), 16)
	local key_1 = tonumber(string.sub(key, 17, 24), 16)
	local key_0 = tonumber(string.sub(key, 25, 32), 16) --LSB
	local _salt = tonumber(salt, 16)

	local IPSRXIDX__BASE		= clear_bits32(dpdkc.read_reg32(port, IPSRXIDX), 12, 1) --clear TABLE and TB_IDX
	local IPSRXIDX__TABLE		= bit.lshift(0x3, 1) --0x3 means KEY table
	local IPSRXIDX__TB_IDX		= bit.lshift(idx, 3)
	local IPSRXIDX__READ		= bit.lshift(0, 30)
	local IPSRXIDX__WRITE		= bit.lshift(1, 31)
	local IPSRXIDX__VALUE = bit.bor(
		IPSRXIDX__BASE,
		IPSRXIDX__TABLE,
		IPSRXIDX__TB_IDX,
		IPSRXIDX__READ,
		IPSRXIDX__WRITE)
	--print("IPSRXIDX__VALUE: 0x"..uhex32(IPSRXIDX__VALUE))

	--TODO: assign configuration fields (valid, proto, decrypt, ipv6) dynamically
	local IPSRXMOD__BASE		= 0x0
	local IPSRXMOD__VALID		= bit.lshift(1, 0) -- 1=valid, 0=invalid
	local IPSRXMOD__PROTO		= bit.lshift(1, 2) -- 1=ESP, 0=AH
	local IPSRXMOD__DECRYPT		= bit.lshift(1, 3) -- 1=decrypt(ESP), 0=authenticate(ESP)
	local IPSRXMOD__IPV6		= bit.lshift(0, 4) -- 1=IPv6, 0=IPv4
	local IPSRXMOD__VALUE = bit.bor(
		IPSRXMOD__BASE,
		IPSRXMOD__VALID,
		IPSRXMOD__PROTO,
		IPSRXMOD__DECRYPT,
		IPSRXMOD__IPV6)

	--prepare registers
	dpdkc.write_reg32(port, IPSRXKEY_3, key_3)
	dpdkc.write_reg32(port, IPSRXKEY_2, key_2)
	dpdkc.write_reg32(port, IPSRXKEY_1, key_1)
	dpdkc.write_reg32(port, IPSRXKEY_0, key_0)
	dpdkc.write_reg32(port, IPSRXSALT, _salt)
	dpdkc.write_reg32(port, IPSRXMOD, IPSRXMOD__VALUE)
	--push to hw
	dpdkc.write_reg32(port, IPSRXIDX, IPSRXIDX__VALUE)
end

function mod.rx_get_key(port, idx)
	if idx > 1023 or idx < 0 then
		error("Idx must be in range 0-1023")
	end

	local IPSRXIDX__BASE		= clear_bits32(dpdkc.read_reg32(port, IPSRXIDX), 12, 1) --clear TABLE and TB_IDX
	local IPSRXIDX__TABLE		= bit.lshift(0x3, 1) --0x3 means KEY table
	local IPSRXIDX__TB_IDX		= bit.lshift(idx, 3)
	local IPSRXIDX__READ		= bit.lshift(1, 30)
	local IPSRXIDX__WRITE		= bit.lshift(0, 31)
	local IPSRXIDX__VALUE = bit.bor(
		IPSRXIDX__BASE,
		IPSRXIDX__TABLE,
		IPSRXIDX__TB_IDX,
		IPSRXIDX__READ,
		IPSRXIDX__WRITE)
	--print("IPSRXIDX__VALUE: 0x"..uhex32(IPSRXIDX__VALUE))

	--pull from hw
	dpdkc.write_reg32(port, IPSRXIDX, IPSRXIDX__VALUE)

	--fetch result
	local key_3 = dpdkc.read_reg32(port, IPSRXKEY_3)
	local key_2 = dpdkc.read_reg32(port, IPSRXKEY_2)
	local key_1 = dpdkc.read_reg32(port, IPSRXKEY_1)
	local key_0 = dpdkc.read_reg32(port, IPSRXKEY_0)
	local _salt = dpdkc.read_reg32(port, IPSRXSALT)
	local _mode = dpdkc.read_reg32(port, IPSRXMOD)

	local valid   = bit.rshift(bit.band(_mode, 0x01), 0)
	local proto   = bit.rshift(bit.band(_mode, 0x04), 2)
	local decrypt = bit.rshift(bit.band(_mode, 0x08), 3)
	local ipv6    = bit.rshift(bit.band(_mode, 0x10), 4)
	local key = uhex32(key_3)..uhex32(key_2)..uhex32(key_1)..uhex32(key_0)

	return key, uhex32(_salt), valid, proto, decrypt, ipv6
end

function mod.rx_set_ip(port, idx, ip_addr)
	if idx > 127 or idx < 0 then
		error("Idx must be in range 0-127")
	end

	local ip, is_ipv4 = parseIPAddress(ip_addr)

	local ip_3 = 0x0
	local ip_2 = 0x0
	local ip_1 = 0x0
	local ip_0 = 0x0
	
	if is_ipv4 == true then
		ip_3 = bswap(ip)
	else
		ip_3 = bswap(ip.uint32[0])
		ip_2 = bswap(ip.uint32[1])
		ip_1 = bswap(ip.uint32[2])
		ip_0 = bswap(ip.uint32[3])
	end

	local IPSRXIDX__BASE		= clear_bits32(dpdkc.read_reg32(port, IPSRXIDX), 12, 1) --clear TABLE and TB_IDX
	local IPSRXIDX__TABLE           = bit.lshift(0x1, 1) --0x1 means IP table
	local IPSRXIDX__TB_IDX          = bit.lshift(idx, 3)
	local IPSRXIDX__READ            = bit.lshift(0, 30)
	local IPSRXIDX__WRITE           = bit.lshift(1, 31)
	local IPSRXIDX__VALUE = bit.bor(
		IPSRXIDX__BASE,
		IPSRXIDX__TABLE,
		IPSRXIDX__TB_IDX,
		IPSRXIDX__READ,
		IPSRXIDX__WRITE)
        --print("IPSRXIDX__VALUE: 0x"..uhex32(IPSRXIDX__VALUE))

	--prepare registers
        dpdkc.write_reg32(port, IPSRXIPADDR_3, ip_3)
        dpdkc.write_reg32(port, IPSRXIPADDR_2, ip_2)
        dpdkc.write_reg32(port, IPSRXIPADDR_1, ip_1)
        dpdkc.write_reg32(port, IPSRXIPADDR_0, ip_0)
        --push to hw
        dpdkc.write_reg32(port, IPSRXIDX, IPSRXIDX__VALUE)
end

function mod.rx_get_ip(port, idx, is_ipv4)
	if idx > 127 or idx < 0 then
		error("Idx must be in range 0-127")
	end
	if is_ipv4 == nil then
		is_ipv4 = true
	end

	local IPSRXIDX__BASE		= clear_bits32(dpdkc.read_reg32(port, IPSRXIDX), 12, 1) --clear TABLE and TB_IDX
	local IPSRXIDX__TABLE           = bit.lshift(0x1, 1) --0x1 means IP table
	local IPSRXIDX__TB_IDX          = bit.lshift(idx, 3)
	local IPSRXIDX__READ            = bit.lshift(1, 30)
	local IPSRXIDX__WRITE           = bit.lshift(0, 31)
	local IPSRXIDX__VALUE = bit.bor(
		IPSRXIDX__BASE,
		IPSRXIDX__TABLE,
		IPSRXIDX__TB_IDX,
		IPSRXIDX__READ,
		IPSRXIDX__WRITE)
	--print("IPSRXIDX__VALUE: 0x"..uhex32(IPSRXIDX__VALUE))

        --pull from hw
        dpdkc.write_reg32(port, IPSRXIDX, IPSRXIDX__VALUE)
	--fetch result
        local ip_3 = dpdkc.read_reg32(port, IPSRXIPADDR_3)
        local ip_2 = dpdkc.read_reg32(port, IPSRXIPADDR_2)
        local ip_1 = dpdkc.read_reg32(port, IPSRXIPADDR_1)
        local ip_0 = dpdkc.read_reg32(port, IPSRXIPADDR_0)

	local ip = nil
	if is_ipv4 == true then
		local ip4 = ffi.new("union ip4_address")
		ip4.uint32 = ip_3
		ip = ip4:getString()
	else
		local ip6 = ffi.new("union ip6_address")
		ip6.uint32[3] = ip_3
		ip6.uint32[2] = ip_2
		ip6.uint32[1] = ip_1
		ip6.uint32[0] = ip_0
		ip = ip6:getString()
	end

	return ip, is_ipv4
end

function mod.rx_set_spi(port, idx, spi, ip_idx)
	if idx > 1023 or idx < 0 then
		error("Idx must be in range 0-1023")
	end
	if spi > 0xFFFFFFFF or spi < 0 then
		error("Spi must be in range 0x0-0xFFFFFFFF")
	end
	if ip_idx > 127 or ip_idx < 0 then
		error("IP_Idx must be in range 0-127")
	end

	local IPSRXIDX__BASE		= clear_bits32(dpdkc.read_reg32(port, IPSRXIDX), 12, 1) --clear TABLE and TB_IDX
	local IPSRXIDX__TABLE           = bit.lshift(0x2, 1) --0x2 means SPI table
	local IPSRXIDX__TB_IDX          = bit.lshift(idx, 3)
	local IPSRXIDX__READ            = bit.lshift(0, 30)
	local IPSRXIDX__WRITE           = bit.lshift(1, 31)
	local IPSRXIDX__VALUE = bit.bor(
		IPSRXIDX__BASE,
		IPSRXIDX__TABLE,
		IPSRXIDX__TB_IDX,
		IPSRXIDX__READ,
		IPSRXIDX__WRITE)
	--print("IPSRXIDX__VALUE: 0x"..uhex32(IPSRXIDX__VALUE))

	--prepare registers
	dpdkc.write_reg32(port, IPSRXSPI, bswap(spi)) --network byte order!
	dpdkc.write_reg32(port, IPSRXIPIDX, ip_idx) --affects only bits 6:0 (i.e. 0-127)
        --push to hw
        dpdkc.write_reg32(port, IPSRXIDX, IPSRXIDX__VALUE)
end

function mod.rx_get_spi(port, idx)
	if idx > 1023 or idx < 0 then
		error("Idx must be in range 0-1023")
	end

	local IPSRXIDX__BASE		= clear_bits32(dpdkc.read_reg32(port, IPSRXIDX), 12, 1) --clear TABLE and TB_IDX
	local IPSRXIDX__TABLE           = bit.lshift(0x2, 1) --0x2 means SPI table
	local IPSRXIDX__TB_IDX          = bit.lshift(idx, 3)
	local IPSRXIDX__READ            = bit.lshift(1, 30)
	local IPSRXIDX__WRITE           = bit.lshift(0, 31)
	local IPSRXIDX__VALUE = bit.bor(
		IPSRXIDX__BASE,
		IPSRXIDX__TABLE,
		IPSRXIDX__TB_IDX,
		IPSRXIDX__READ,
		IPSRXIDX__WRITE)
	--print("IPSRXIDX__VALUE: 0x"..uhex32(IPSRXIDX__VALUE))

        --pull from hw
        dpdkc.write_reg32(port, IPSRXIDX, IPSRXIDX__VALUE)
	--fetch result
	local spi    = dpdkc.read_reg32(port, IPSRXSPI) --network byte order!
	local ip_idx = dpdkc.read_reg32(port, IPSRXIPIDX)

	return bswap(spi), bit.band(ip_idx, 0xffffff80)
end

return mod