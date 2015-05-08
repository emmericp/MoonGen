local mod = {}

-- read_reg32(uint8_t port, uint32_t reg)
-- write_reg32(uint8_t port, uint32_t reg, uint32_t val)
local dpdkc	= require "dpdkc"
local dpdk	= require "dpdk"

-- Intel X540 registers
local SECTXCTRL		= 0x00008800
local SECRXCTRL		= 0x00008D00
local SECTXSTAT		= 0x00008804
local SECRXSTAT		= 0x00008D04
local SECTXMINIFG	= 0x00008810
local SECTXBUFFAF	= 0x00008808

function dump_regs(port)
	print("===== DUMP REGS =====")
	local reg = dpdkc.read_reg32(port, SECTXCTRL)
	printf("SECTXCTRL: %#010x", reg)
	local reg = dpdkc.read_reg32(port, SECRXCTRL)
	printf("SECRXCTRL: %#010x", reg)
	local reg = dpdkc.read_reg32(port, SECTXSTAT)
	printf("SECTXSTAT: %#010x", reg)
	local reg = dpdkc.read_reg32(port, SECRXSTAT)
	printf("SECRXSTAT: %#010x", reg)
	local reg = dpdkc.read_reg32(port, SECTXMINIFG) --TODO: check wrong init: 0x1001 instead of 0x1
	printf("SECTXMINIFG: %#010x", reg)
	local reg = dpdkc.read_reg32(port, SECTXBUFFAF)
	printf("SECTXBUFFAF: %#010x", reg)
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

return mod
