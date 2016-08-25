local ffi = require "ffi"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
require "utils"

local mod = {}

local mg_kni = {}
mod.mg_kni = mg_kni
mg_kni.__index = mg_kni

ffi.cdef[[
struct rte_kni;
struct rte_kni * mg_create_kni(uint8_t port_id, uint8_t core_id, void* mempool_ptr, const char name[]);
unsigned rte_kni_tx_burst 	( 	struct rte_kni *  	kni,
		struct rte_mbuf **  	mbufs,
		unsigned  	num 
	);
unsigned rte_kni_rx_burst 	( 	struct rte_kni *  	kni,
		struct rte_mbuf **  	mbufs,
		unsigned  	num 
	);
int rte_kni_handle_request 	( 	struct rte_kni *  	kni	);
unsigned mg_kni_tx_single(struct rte_kni * kni, struct rte_mbuf * mbuf);
void rte_kni_close 	( 	void  		);
int rte_kni_release 	( 	struct rte_kni *  	kni	);
void rte_kni_init(unsigned int max_kni_ifaces);
]]

function mod.createKNI(core, device, mempool, name)
  --printf("kni C pointer print:")
  --printPtr(mempool)
  core = core or 0
  --printf("port id %d", device.id)
  --printf("in KNI ptr memp %p", mempool)
  --printPtr(mempool)
  local kni = ffi.C.mg_create_kni(device.id, core, mempool, name)
  --printPtr(mempool)
  --printf("KNI should be nil = %p ,, mempool = %p", kni, mempool)
  --if(kni == nil)then
  --  printf("KNI == NIL !!!")
  --else
  --  printf("KNI not nil")
  --end
  return setmetatable({
    kni = kni,
    core = core,
    device = device
  }, mg_kni)
end

function mg_kni:rxBurst(bufs, nmax)
  return ffi.C.rte_kni_rx_burst(self.kni, bufs.array, nmax)
end

function mg_kni:txSingle(mbuf)
  ffi.C.mg_kni_tx_single(self.kni, mbuf)
end

function mg_kni:handleRequest()
  ffi.C.rte_kni_handle_request(self.kni)
end

function mg_kni:release()
  return ffi.C.rte_kni_release(self.kni)
end

function mod.init(num)
  return ffi.C.rte_kni_init(num)
end

function mod.close()
  ffi.C.rte_kni_close()
end

return mod
