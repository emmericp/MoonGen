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

function dump_regs(port)
	print("===== DUMP REGS =====")
	local reg = dpdkc.read_reg32(port, SECTXCTRL)
	printf("SECTXCTRL: 0x%x", reg)
	local reg = dpdkc.read_reg32(port, SECRXCTRL)
	printf("SECRXCTRL: 0x%x", reg)
	local reg = dpdkc.read_reg32(port, SECTXSTAT)
	printf("SECTXSTAT: 0x%x", reg)
	local reg = dpdkc.read_reg32(port, SECRXSTAT)
	printf("SECRXSTAT: 0x%x", reg)
	local reg = dpdkc.read_reg32(port, SECTXMINIFG) --TODO: check wrong init: 0x1001 instead of 0x1
	printf("SECTXMINIFG: 0x%x", reg)
	local reg = dpdkc.read_reg32(port, SECTXBUFFAF)
	printf("SECTXBUFFAF: 0x%x", reg)
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
-- @idx: Index into SA TX table
-- @key: 128 bit AES key  (as hex string)
-- @salt: 32 bit AES salt (as hex string)
function mod.tx_add_key(port, idx, key, salt)
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
	local _salt  = tonumber(salt, 16)

	local reg = dpdkc.read_reg32(port, IPSTXIDX)
	printf("IPSTXIDX: 0x%x", reg)

	printf("key_3: 0x%x", key_3)
	printf("key_2: 0x%x", key_2)
	printf("key_1: 0x%x", key_1)
	printf("key_0: 0x%x", key_0)
	printf("salt:  0x%x", _salt)

	--prepare registers
	dpdkc.write_reg32(port, IPSTXKEY_3, key_3)
	dpdkc.write_reg32(port, IPSTXKEY_2, key_2)
	dpdkc.write_reg32(port, IPSTXKEY_1, key_1)
	dpdkc.write_reg32(port, IPSTXKEY_0, key_0)
	dpdkc.write_reg32(port, IPSTXSALT, _salt)
	--push to hw
	--TODO: make use of idx argument
	dpdkc.write_reg32(port, IPSTXIDX, 0x80000000) --TODO: modify only relevant bits, IPS_TX_EN=0, idx/SA_IDX=0
	--TODO: pass SA_IDX via 'TX context descriptor' to use this SA!

	local reg = dpdkc.read_reg32(port, IPSTXIDX)
	printf("IPSTXIDX: 0x%x", reg)
end

function mod.tx_get_key(port, idx)
	--pull from hw
	--TODO: make use of idx argument
	dpdkc.write_reg32(port, IPSTXIDX, 0x40000000) --TODO. modify only relevant bits, IPS_TX_EN=0, idx/SA_IDX=0
	--dpdkc.write_reg32(port, IPSTXIDX, 0x40000008) --TODO. modify only relevant bits, IPS_TX_EN=0, idx/SA_IDX=1

	local key_3 = dpdkc.read_reg32(port, IPSTXKEY_3)
	local key_2 = dpdkc.read_reg32(port, IPSTXKEY_2)
	local key_1 = dpdkc.read_reg32(port, IPSTXKEY_1)
	local key_0 = dpdkc.read_reg32(port, IPSTXKEY_0)
	local salt  = dpdkc.read_reg32(port, IPSTXSALT)

	printf("key_3: 0x%x", key_3)
	printf("key_2: 0x%x", key_2)
	printf("key_1: 0x%x", key_1)
	printf("key_0: 0x%x", key_0)
	printf("salt:  0x%x", salt)
end

return mod
