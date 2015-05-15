local mod = {}

local dpdkc	= require "dpdkc"
local dpdk	= require "dpdk"

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

-- Helper function to return padded, unsigned 32bit hex string.
function uhex32(x)
	return bit.tohex(x, 8)
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
	local reg = dpdkc.read_reg32(port, SECTXMINIFG) --TODO: check wrong init: 0x1001 instead of 0x1
	print("SECTXMINIFG: 0x"..uhex32(reg))
	local reg = dpdkc.read_reg32(port, SECTXBUFFAF)
	print("SECTXBUFFAF: 0x"..uhex32(reg))
end

function mod.enable(port)
	printf("IPsec enable, port: %d", port)
	dump_regs(port)

	dpdkc.write_reg32(port, SECTXCTRL, 0x1) --TODO: only modify TX_DIS bit
	dpdkc.write_reg32(port, SECRXCTRL, 0x1) --TODO: only modify RX_DIS bit
	--TODO: check only relevant bits
	while dpdkc.read_reg32(port, SECTXSTAT) ~= 0x1 or dpdkc.read_reg32(port, SECRXSTAT) ~= 0x1 do
		print("Waiting for registers to be asserted by hardware...")
		dump_regs()
	end
	dpdkc.write_reg32(port, SECTXCTRL, 0x0) --TODO: only modify TX_DIS bit
	dpdkc.write_reg32(port, SECRXCTRL, 0x0) --TODO: only modify RX_DIS bit
	dpdkc.write_reg32(port, SECTXMINIFG, 0x3) --TODO: only modify MINSECIFG bits
	dpdkc.write_reg32(port, SECTXCTRL, 0x4) --TODO only modify STORE_FORWARD bit
	dpdkc.write_reg32(port, SECTXBUFFAF, 0x15) --TODO: only modify FULLTHRESH bit

	dpdk.sleepMillis(1000)
	dump_regs(port)
end

function mod.disable(port)
	printf("IPsec disable, port: %d", port)
	dump_regs(port)

	dpdkc.write_reg32(port, SECTXCTRL, 0x1) --TODO: only modify TX_DIS bit
	dpdkc.write_reg32(port, SECRXCTRL, 0x1) --TODO: only modify RX_DIS bit
	--TODO: check only relevant bits
	while dpdkc.read_reg32(port, SECTXSTAT) ~= 0x1 or dpdkc.read_reg32(port, SECRXSTAT) ~= 0x1 do
		print("Waiting for registers to be asserted by hardware...")
		dump_regs()
	end
	--TODO: clear IPSTXIDX.IPS_TX_EN
	--TODO: clear IPSRXIDX.IPS_RX_EN
	dpdkc.write_reg32(port, SECTXCTRL, 0x1) --TODO: only modify TX_DIS bit
	dpdkc.write_reg32(port, SECRXCTRL, 0x1) --TODO: only modify RX_DIS bit
	dpdkc.write_reg32(port, SECTXBUFFAF, 0x250) --TODO: only modify FULLTHRESH bit
	dpdkc.write_reg32(port, SECTXCTRL, 0x0) --TODO: only modify TX_DIS bit
	dpdkc.write_reg32(port, SECRXCTRL, 0x0) --TODO: only modify RX_DIS bit

	dpdk.sleepMillis(1000)
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

	local IPSTXIDX__BASE		= 0x0
	local IPSTXIDX__IPS_TX_EN	= bit.lshift(0, 0) --TODO: should probably be enabled
	local IPSTXIDX__SA_IDX		= bit.lshift(idx, 3)
	local IPSTXIDX__READ		= bit.lshift(0, 30)
	local IPSTXIDX__WRITE		= bit.lshift(1, 31)
	local IPSTXIDX__VALUE = bit.bor(
		IPSTXIDX__BASE,
		IPSTXIDX__IPS_TX_EN,
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
		error("Idx must be in range 0..1023")
	end

	local IPSTXIDX__BASE		= 0x0
	local IPSTXIDX__IPS_TX_EN	= bit.lshift(0, 0) --TODO: should probably be enabled
	local IPSTXIDX__SA_IDX		= bit.lshift(idx, 3)
	local IPSTXIDX__READ		= bit.lshift(1, 30)
	local IPSTXIDX__WRITE		= bit.lshift(0, 31)
	local IPSTXIDX__VALUE = bit.bor(
		IPSTXIDX__BASE,
		IPSTXIDX__IPS_TX_EN,
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

	local IPSRXIDX__BASE		= 0x0
	local IPSRXIDX__IPS_RX_EN	= bit.lshift(0, 0) --TODO: should probably be enabled
	local IPSRXIDX__TABLE		= bit.lshift(3, 1) --3 means KEY table
	local IPSRXIDX__TB_IDX		= bit.lshift(idx, 3)
	local IPSRXIDX__READ		= bit.lshift(0, 30)
	local IPSRXIDX__WRITE		= bit.lshift(1, 31)
	local IPSRXIDX__VALUE = bit.bor(
		IPSRXIDX__BASE,
		IPSRXIDX__IPS_RX_EN,
		IPSRXIDX__TABLE,
		IPSRXIDX__TB_IDX,
		IPSRXIDX__READ,
		IPSRXIDX__WRITE)
	--print("IPSRXIDX__VALUE: 0x"..uhex32(IPSRXIDX__VALUE))

	--prepare registers
	dpdkc.write_reg32(port, IPSRXKEY_3, key_3)
	dpdkc.write_reg32(port, IPSRXKEY_2, key_2)
	dpdkc.write_reg32(port, IPSRXKEY_1, key_1)
	dpdkc.write_reg32(port, IPSRXKEY_0, key_0)
	dpdkc.write_reg32(port, IPSRXSALT, _salt)
	--push to hw
	dpdkc.write_reg32(port, IPSRXIDX, IPSRXIDX__VALUE)
end

function mod.rx_get_key(port, idx)
	if idx > 1023 or idx < 0 then
		error("Idx must be in range 0..1023")
	end

	local IPSRXIDX__BASE		= 0x0
	local IPSRXIDX__IPS_RX_EN	= bit.lshift(0, 0) --TODO: should probably be enabled
	local IPSRXIDX__TABLE		= bit.lshift(3, 1) --3 means KEY table
	local IPSRXIDX__TB_IDX		= bit.lshift(idx, 3)
	local IPSRXIDX__READ		= bit.lshift(1, 30)
	local IPSRXIDX__WRITE		= bit.lshift(0, 31)
	local IPSRXIDX__VALUE = bit.bor(
		IPSRXIDX__BASE,
		IPSRXIDX__IPS_RX_EN,
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
	local _salt  = dpdkc.read_reg32(port, IPSRXSALT)

	local key = uhex32(key_3)..uhex32(key_2)..uhex32(key_1)..uhex32(key_0)

	return key, uhex32(_salt)
end
return mod
