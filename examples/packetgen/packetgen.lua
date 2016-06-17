--[[
  
   Copyright (C) 2016 Netronome Systems, Inc. All rights reserved.

   Description : Generates a bursty traffic pattern using the rules specified
                 below.

   -- All packets generated will share the same source IP, source MAC and size
      profile (fixed or IMIX).
   -- The destination IP and MAC are selected sequentially in the following 
      pattern:

   a) The stream number is set to 0.
   b) The stream base is calculated by multiplying the stream number with the 
      MAC and IP stride.
   c) The burst number is set to 0.
   d) The flow number is set to 0.
   e) A packet is generated with the destination IP and MAC set to "stream 
      base" + "flow number".
   f) The flow number is increased, if it is less than the number of flows per 
      stream, loop back to (e), else continue to (g).
   g) The burst number is increased, if it is less than the number of bursts 
      per stream, loop back to (d), else continue to (h).
   h) The stream base is incremented, if it is less than the number of streams,
      loop back to (a).

   -- This reults in a set of streams that are separated by the MAC and IP 
      stride and repeat in bursts. The destination IP and MAC increase in 
      lock-step.
   -- Packet size can be constant, or selected from a 7:4:1 IMIX profile with 
      packet sizes 1514, 570, and 64, respectively. 
--]]

local moongen  = require "dpdk"      
local dpdkc    = require "dpdkc"       
local memory   = require "memory"
local device   = require "device"
local ffi      = require "ffi"
local log      = require "log"
local bit      = require "bit"

local lshift    , rshift    , band    , bswap     , ror = 
      bit.lshift, bit.rshift, bit.band, bit.bswap , bit.ror

-- State of the packet generator.
local state = "canrun"

-- Configuration table for each core. Each coreQconf table has the following 
-- elements:
--
--    nTxPorts    : Number of tx ports for the core.
--    txPortList  : List of tx ports for the core.
--    rxPorts     : Number of rxports for the core.
--    rxPortList  : Lits of rx ports for the core.
local coreQconf = {}

-- Table of ethernet devices, each of these 
-- devices wrapps the tx and rx queues.
local devices = {}

-- Table for the stats tables for each port.
-- Each stats table is the stats table below.
local portstats = {}

-- Table for stats per core. This 
-- is a table of portstats tables.
local cstats = {}

-- Table for the statistics for each port.
--
--   - rxBytes        : Number of received bytes.
--   - prevRxBytes    : Number of received bytes at the prev iteration.
--   - rxPackets      : Number of received packets.
--   - prevRxPackets  : Number of received packets at the prev iteration.
--   - txBytes        : Number of transmitted bytes.
--   - prevTxBytes    : Number of transmitted bytes at the prev iteration.
--   - txPackets      : Number of transmitted packets.
--   - prevTxPackets  : Number of transmitted packets at the prev iteration.
--   - rxDropped      : Number of dropped receive packets.
--   - txDropped      : Number of dropped transmit packets.
--   - txBursts       : Number of transmit bursts.
--   - txShort        : Number of generated but not transmitted packets.
--   - rxLatPackets   : Number of received packets with latency timestamps.
--   - rxMeanLatency  : Average latency of the packets.
--   - rxM2Latency    : Squared average of the latency of the packets.-
--   - elapsedTime    : Time elapsed for the last iteration.
local stats = {
    rxBytes       = 0 ,
    prevRxBytes   = 0 ,
    rxPackets     = 0 ,
    prevRxPackets = 0 , 
    txBytes       = 0 ,
    prevTxBytes   = 0 ,
    txPackets     = 0 ,
    prevTxPackets = 0 , 
    rxDropped     = 0 ,
    txDropped     = 0 ,
    txBursts      = 0 ,
    txShort       = 0 , 
    rxLatPackets  = 0 ,
    rxMeanLatency = 0 ,
    rxM2Latency   = 0 , 
    elapsedTime   = 0
}

-- Table for packetgen params.
local params = {
    cores              = 1                                ,
    txPortsPerCore     = 1                                ,
    totalTxPorts       = 1                                ,
    rxPortsPerCore     = 1                                ,
    portmask           = "0x1"                            ,
    flowsPerStream     = 2047                             ,
    numberOfStreams    = 1                                ,
    burstPerStream     = 1                                ,
    txBurstSize        = 32                               ,
    rxBurstSize        = 32                               ,
    txDelta            = 0                                ,
    totalFlows         = 0                                ,
    packetSize         = 64                               ,
    mustImix           = false                            ,
    timerPeriod        = 1                                ,
    ethSrcBaseNum      = 0x000d30596955                   ,
    ethSrcBase         = "00:0d:30:59:69:55"              ,
    ethSrcVaryNum      = 0                                ,
    ethSrcVary         = "00:00:00:00:00:00"              ,
    ethDstBaseNum      = 0x5452deadbeef                   ,
    ethDstBase         = "54:52:de:ad:be:ef"              ,
    ethDstVaryNum      = 1                                ,
    ethDstVary         = "00:00:00:00:00:01"              ,
    ethStrideNum       = 0                                ,
    ethStride          = "00:00:00:00:00:00"              , 
    ipSrcBaseNum       = 0                                ,
    ipSrcBase          = "192.168.50.10"                  ,
    ipSrcVaryNum       = 0                                ,
    ipSrcVary          = "0.0.0.0"                        ,
    ipDstBaseNum       = 0                                ,
    ipDstBase          = "192.168.60.10"                  ,
    ipDstVaryNum       = 1                                ,
    ipDstVary          = "0.0.0.1"                        ,
    ipStrideNum        = 0                                , 
    ipStride           = "0.0.0.0"                        ,
    portSrcBase        = 4096                             ,
    portSrcVary        = 1                                ,
    portDstBase        = 2048                             ,
    portDstVary        = 0                                ,
    portStride         = 0                                ,
    defaultPayload     = "\x42\x01\x02\x03 DPDK Payload"  ,
    defaultPayloadSize = 17                               ,
    nbRxd              = 1024                             ,
    nbTxd              = 1024                             ,
    nbPorts            = 0                                ,
    paramDisplay       = 3000
}

-- Defines parameters for a burst.
--
--  counter  : Counter for creating burst pattern.
--  flowid   : The flow ID of the burst.
--  streamid : The stream ID of the burst.
--  prevtsc  : The previous clock count.
--  currtsc  : The current clock count.
--  difftsc  : The difference between the clock counts.
local bparams = {
    counter  = 0 ,
    flowid   = 0 ,
    streamid = 0 ,
    prevtsc  = 0 ,
    currtsc  = 0 , 
    difftsc  = 0
}

-- General constants used by packetgen ---------------------------------------

MAX_RX_QUEUES_PER_CORE  = 16
MAX_RX_BURST_SIZE       = 128
MAX_TX_BURST_SIZE       = 128
ETHER_TYPE_IPv4         = 0x0800
MAX_SEG_LENGTH          = 20000
ETHER_ADDR_LEN          = 6            
ETHER_HEADER_LENGTH     = 14          
IP_HEADER_LENGTH        = 20            
UDP_HEADER_LENGTH       = 8            
TOTAL_HEADER_LENGTH     = ETHER_HEADER_LENGTH 
                        + IP_HEADER_LENGTH
                        + UDP_HEADER_LENGTH

-- This is the max number of mbufs than 
-- can be allocated from a single mempool.
MAX_MEMPOOL_SIZE = 2047

-- Global start time across all threads.
local globalStart = moongen.getTime()

-- @brief Defines the main function for packetgen.
function master(...)
    local continue = parseArgs(params, ...)
    if continue == false then 
        os.exit() 
    end

    local portmask = 0ULL + tonumber(params.portmask, 16)
    params.nbPorts = device.numDevices()

    -- Init the stats for each port.
    for portid = 0, params.nbPorts - 1 do
        if band(portmask, lshift(1, portid)) >= 1 then 
            portstats[portid + 1] = deepCopy(stats)
        end
    end

    -- Initialize the core Q confs -- note that although the core ids 
    -- go from 0 -> params.cores - 1, because of the 1 indexed array we 
    -- use 1 -> params.cores, to avoid having to index with tostring(coreid)
    for coreid = 1, params.cores do
        coreQconf[coreid] = {
            nTxPorts   = 0  ,
            txPortList = {} ,
            nRxPorts   = 0  ,
            rxPortList = {} 
        }
    end

    -- Each core has an array of stats for each port. At the end, the stats
    -- from a port across all the cores doing something on that port are 
    -- aggregated
    for i = 1, #coreQconf do
        cstats[i] = deepCopy(portstats)
    end

    -- Allocate tx cores for each port first.
    -- NOTE: The coreid is the actual value of the coreid (physical), 
    --       so we need to add 1 when indexing into lcoreQconf table.
    local txPorts = {}
    local coreid  = 0
    for portid = 0, params.nbPorts - 1 do 
        if band(portmask, lshift(1, portid)) >= 1 and 
           #txPorts < params.totalTxPorts then 
	          while coreQconf[coreid + 1].nTxPorts 
	                >= params.txPortsPerCore do
	              coreid = coreid + 1
	              if coreid >= params.cores then
                    print("Error: Not enough cores for tx port alloc!")
		                return
	              end
	          end

	          -- Update the list of ports used for tx
	          -- since these can't be used for rx.
	          local inTxList = false
	          for i = 1, #txPorts do
	              if txPorts[i] == portid then 
		                inTxList = true
	              end
	          end
	          if inTxList == false then
	              txPorts[#txPorts + 1] = portid
	          end

	          -- Have a valid coreid.
	          local coreidx = coreid + 1
	          local portidx = coreQconf[coreidx].nTxPorts + 1

	          coreQconf[coreidx].txPortList[portidx] = portid
	          coreQconf[coreidx].nTxPorts            = portidx

	          print(string.format("Core %u: TX port %u", coreid, portid))
        end
    end

    -- Display message if no ports are allocated for transmission.
    if #txPorts == 0 then
        print("Note: No ports are allocated for TX!")
    end

    -- Allocate RX cores for each port
    coreid = coreid + 1
    if coreid >= params.cores then 
        print("Note: Not enough cores for rx port alloc! " ..
              "Packetgen will only transmit!")
    else 
        for portid = 0, params.nbPorts - 1 do
            -- Check if the port is being used to transmit
            local canContinue = true
            for i = 1, #txPorts do
                if txPorts[i] == portid then 
                    canContinue = false
                end
            end

            if band(portmask, lshift(1, portid)) >= 1 and canContinue then 
                while coreid < params.cores and 
                      coreQconf[coreid + 1].nRxPorts >= params.rxPortsPerCore do
                    coreid = coreid + 1
                    if coreid >= params.cores then
                        print("Note: Not enough cores for rx port alloc! " ..
                              "Packetgen will receive on only the cores " ..
                              "which have already been configured!")
                        break
                    end
                end
                if coreid < params.cores then 
                    -- Have a valid coreid
                    local coreidx = coreid + 1
                    local portidx = coreQconf[coreidx].nRxPorts + 1

                    coreQconf[coreidx].rxPortList[portidx] = portid
                    coreQconf[coreidx].nRxPorts 	         = portidx

                    print(string.format("Core %u: RX port %u", coreid, portid))
                end
           end 
        end
    end

    -- Configure and initialize each device.
    for portid = 0, params.nbPorts do
        if band(portmask, lshift(1, portid)) >= 1 then 
            devices[portid + 1] = device.config{
                port     = portid ,
                rxQueues = 1      ,   -- Only 1 supported for now
                txQueues = 1          -- Only 1 supported for now
            }
            devices[portid + 1]:setPromisc(true)

            print(string.format("Port %u: Mac %s",
                portid, devices[portid + 1]:getMacString()))
        end
    end

    -- Print the parameters of the run, to make
    -- sure that the generation is correct.
    params:print()
    
    -- Sleep to keep the params displayed.
    moongen.sleepMillis(params.paramDisplay)

    globalStart = moongen.getTime()
    -- Launch the tx and rx cores.
    for i = 1, #coreQconf do 
        -- If the coreQconf has a tx port, then make it tx,
        -- otherewise the core can be used for rx.
        if coreQconf[i].nTxPorts >= 1 then 
            moongen.launchLua(
                "coreBenchTx", i, coreQconf, devices, params, cstats[i]
            )
        elseif coreQconf[i].nRxPorts >= 1 then
           moongen.launchLua(
               "coreBenchRx", i, coreQconf, devices, params, cstats[i]
           )
        end
    end
    moongen.waitForSlaves()
end

-- @brief Performs an iteration of the burst generation. If enough 
--        time has passed the packets are sent, otherwise the 
--        function just exits.
-- @param coreid    The id of the core using generation the burst.
-- @param qconfs    The configuration tables for the cores.
-- @param portid    The id of the port to generate the burst on.
-- @param txqueue   The queue to send the burst on.
-- @param pstats    The stats for the port.
-- @param pgparams  The packetgen params for the packet generation.
-- @param btxparams The params for the burst type.
-- @param stream    The stream to send for the burst.
function txBurstGenIter(coreid, qconfs  , portid   , txqueue, 
                        pstats, pgparams, btxparams, stream ) 
    -- If enough time has passed to achieve the requested rate.
    if btxparams.difftsc > pgparams.txDelta then 
        pstats[portid].txBursts = pstats[portid].txBursts + 1

        local nbtx = 0
        for i = 1, pgparams.burstPerStream do
            for _, flow in ipairs(stream.bufArrays) do
                for _, buf in ipairs(flow) do
                    updateTimestamp(buf)
                end
                nbtx = nbtx + txqueue:send(flow)
            end
        end

        pstats[portid].txPackets = pstats[portid].txPackets + nbtx

	      for _, flow in ipairs(stream.bufArrays) do 
            for _, buf in ipairs(flow) do 
                pstats[portid].txBytes = pstats[portid].txBytes + 
                    (pgparams.burstPerStream * buf.pkt_len)
            end
        end

        if nbtx < pgparams.txBurstSize then 
            pstats[portid].txShort = pstats[portid].txShort + 1
        end

        btxparams.prevtsc = btxparams.currtsc
    end
end

-- @brief Launces a core for benchmark tx  mode.
-- @param coreid   The id of the core in the coreQconf array.
-- @param qconfs   The array of core Q configurations.
-- @param devices  The ethernet devices to use (ports).
-- @param pgparams The parameters for the packet generation.
-- @param pstats   The stats for all ports
function coreBenchTx(coreid, qconfs, devices, pgparams, pstats)
    print(string.format("Launching Core: %u, Mode: TX", 
          coreid - 1))

    -- The tx port is always the first in the list
    -- as is the queue for the device.
    local btxparams = deepCopy(bparams)
    local portid    = qconfs[coreid].txPortList[1] + 1
    local txqueue   = devices[portid]:getTxQueue(0)
 
    -- All flows to send
    local streams 	     = {}
    local bufArrsPerFlow = 0

    -- Note: Using more than 2047 flows per stream causes 
    --       causes a performance hit because more than 
    --       one mbuf is required for the stream, due to 
    --       the 2047 packet limit per mbuf.
    if pgparams.flowsPerStream > MAX_MEMPOOL_SIZE then
        bufArrsPerFlow = math.floor(pgparams.flowsPerStream
		                   / MAX_MEMPOOL_SIZE) + 1
    else
	      bufArrsPerFlow = 1
    end

    -- Allocate mbuf's for each of the unique flows.
    for i = 1, pgparams.numberOfStreams do
        streams[i] = {
            mempools  = {},
            bufArrays = {}
        }
        for j = 1, bufArrsPerFlow do
            -- This can allocate 2047 mbufs.
            streams[i].mempools[j] = memory:createMemPool(
                function(buf)
                    buf:getUdpPacket():fill{
                        pktLength   = pgparams.packetSize - 4,
                        ethLength   = ethLength             
                    }
                end
            )
           
            -- Determine how many bufs to get from the mpool.
            local numBufs = 0
	          if bufArrsPerFlow == 1 or j < bufArrsPerFlow then 
                if pgparams.flowsPerStream < MAX_MEMPOOL_SIZE then
		                numBufs = pgparams.flowsPerStream
                else 
                    numBufs = MAX_MEMPOOL_SIZE
                end
            elseif j == bufArrsPerFlow then 
		            numBufs = math.fmod(pgparams.flowsPerStream,
				                            MAX_MEMPOOL_SIZE)
            end 

            -- Allocate bufs from the pool
	          streams[i].bufArrays[j] = streams[i].mempools[j]:bufArray(numBufs)
        end
    end

    -- Go through each of the mbufs and modify them.
    for i, stream in ipairs(streams) do
        for j, bufArr in ipairs(stream.bufArrays) do
            if pgparams.mustImix then 
                pgparams.packetSize = imixSize()
            end 

            bufArr:alloc(pgparams.packetSize)

	          for _, buf in ipairs(bufArr) do
                btxparams.flowid   = math.fmod(
		                btxparams.counter, pgparams.flowsPerStream) 
                btxparams.streamid = math.floor(
                    btxparams.counter /  pgparams.flowsPerStream)

                buildTxFrame(portid, buf, btxparams, pgparams)

                btxparams.counter = math.fmod(
		                btxparams.counter + 1, pgparams.totalFlows)
	          end

            -- Offload the checksums 
            bufArr:offloadUdpChecksums()
	      end
    end

    local startTime   = moongen.getTime()
    local globalIter  = 0
    local canPrint    = 1
    while state == "canrun" do
        -- Generate and send bursts
        for _, stream in ipairs(streams) do
            btxparams.currtsc = tonumber(moongen:getCycles())
            btxparams.difftsc = btxparams.currtsc - btxparams.prevtsc

            txBurstGenIter(coreid, qconfs  , portid   , txqueue,
                           pstats, pgparams, btxparams, stream )
        end

        -- Check if its time to print stats.
        globalIter = math.fmod(
                         math.floor(moongen.getTime() - globalStart), 
                         pgparams.cores       * 
                         pgparams.timerPeriod + 
                         pgparams.timerPeriod
                     )
        if globalIter == ((coreid - 1) * pgparams.timerPeriod) and
           canPrint   == 1 then
            canPrint = 0
            os.execute("clear")

            pstats[portid].elapsedTime = moongen.getTime() - startTime

            pstats[portid]:print(moongen:getCore(), portid - 1)

            pstats[portid].prevTxPackets = pstats[portid].txPackets
            pstats[portid].prevTxBytes   = pstats[portid].txBytes

            startTime = moongen.getTime()
        elseif globalIter == coreid * pgparams.timerPeriod and
               canPrint   == 0 then
            canPrint = 1
        end
    end
end

-- @brief Launches a core for benchmark rx mode. 
-- @param coreid   The id of the core in the coreQconf array.
-- @param qconfs   The array of core Q configurations.
-- @param devices  The ethernet devices to use (ports).
-- @param pgparams The parameters for the packet generation.
-- @param pstats   The stats for all ports.
function coreBenchRx(coreid, qconfs, devices, pgparams, pstats)
    print(string.format("Launching Core: %u, Mode: RX", 
          coreid - 1))
    
    local latency      = 0
    local latencyDelta = 0
    local globalIter   = 0
    local canPrint     = 1
    local rxburst      = memory.bufArray(MAX_RX_BURST_SIZE)
    local startTime    = moongen.getTime()
    local elapsedTime  = 0
    local rxPackets    = 0

    while state == "canrun" do
        for i = 1, qconfs[coreid].nRxPorts do
            portid  = qconfs[coreid].rxPortList[i] + 1
            rxqueue = devices[portid]:getRxQueue(0)

            -- Receive the bursts for the port
            rxPackets                = rxqueue:recv(rxburst)
            pstats[portid].rxPackets = pstats[portid].rxPackets + rxPackets
            pstats[portid].rxDropped = pstats[portid].rxDropped + rxPackets

            for i = 1, rxPackets do
                pstats[portid].rxBytes = pstats[portid].rxBytes 
                                       + rxburst[i].pkt_len

                latency = calculateLatency(rxburst[i])
                if latency ~= 0 then 
                    pstats[portid].rxLatPackets 
                                 = pstats[portid].rxLatPackets + 1
                    latencyDelta = latency - pstats[portid].rxMeanLatency

                    pstats[portid].rxMeanLatency = pstats[portid].rxMeanLatency 
                        + (latencyDelta / pstats[portid].rxLatPackets)
                    pstats[portid].rxM2Latency   = pstats[portid].rxM2Latency +
                        latencyDelta * (latency - pstats[portid].rxMeanLatency)
                end 
            end
            simpleDrop(rxburst) 
        end

        -- Check if its time to print stats.
        globalIter = math.fmod(
                        math.floor(moongen.getTime() - globalStart), 
                        pgparams.cores       * 
                        pgparams.timerPeriod + 
                        pgparams.timerPeriod
                     )
        if globalIter == ((coreid - 1) * pgparams.timerPeriod) and
           canPrint   == 1 then
            canPrint = 0
            os.execute("clear")
                
            elapsedTime = moongen.getTime() - startTime 
            for i = 1, qconfs[coreid].nRxPorts do
                portid = qconfs[coreid].rxPortList[i] + 1
                if pstats[portid] ~= nil then 
                    pstats[portid].elapsedTime = elapsedTime
                    pstats[portid]:print(moongen.getCore(), portid - 1)

                    pstats[portid].prevRxPackets = pstats[portid].rxPackets
                    pstats[portid].prevRxBytes   = pstats[portid].rxBytes
                end
            end
            startTime = moongen.getTime()
        elseif globalIter == coreid * pgparams.timerPeriod and
               canPrint   == 0 then
            canPrint = 1
        end
    end
end

-- @brief Updates the timestamp for a packet. The first 8 bytes are used as 
--        the timestamp.
-- @param buf The buffer to update the timestampof.
function updateTimestamp(buf)
    local pkt             = buf:getUdpPacket()
    local cycles          = moongen:getCycles()
    pkt.payload.uint64[0] = cycles
end

-- @brief Gets the timestamp from a packet and then calculates the latency
-- @param buf The buffer to get the timestamp from and then calculate the
--        latency.
function calculateLatency(buf)
    local pkt       = buf:getUdpPacket()
    local cycles    = tonumber(moongen:getCycles())
    local timestamp = tonumber(pkt.payload.uint64[0])
    local latency   = 0

    if timestamp ~= 0 then 
        latency = tonumber(cycles - timestamp) 
                / tonumber(moongen:getCyclesFrequency())
    end
    return latency
end

-- @brief Builds a frame for transmission.
-- @param portid    The portid to use for the calculations.
-- @param buf       The buf wrapper for the packet (rte_mbuf wrapper).
-- @praam btxparams The parameters for the burst.
-- @param pgparams  The general parameters for packetgen.
function buildTxFrame(portid, buf, btxparams, pgparams)

    -- Determine variation parameters
    local varyEth  = pgparams.ethStrideNum * btxparams.streamid 
                   + btxparams.flowid
    local varyIp   = pgparams.ipStrideNum * btxparams.streamid 
                   + btxparams.flowid
    local varyPort = pgparams.portStride * btxparams.streamid 
                   + btxparams.flowid
    local ethSrc   = pgparams.ethSrcVaryNum * varyEth 
                   + pgparams.ethSrcBaseNum + portid   
    local ethDst   = pgparams.ethDstBaseNum + pgparams.ethDstVaryNum * varyEth

    -- FCS is 4 bytes
    local frameSize = pgparams.packetSize - 4
    local ethLength = ETHER_HEADER_LENGTH          
    local ipLength  = frameSize - ethLength 
    local udpLength = ipLength  - IP_HEADER_LENGTH

    -- Create IP and port addresses
    local ipSrcAddr = pgparams.ipSrcVaryNum * varyIp
                    + pgparams.ipSrcBaseNum + portid
    local ipDstAddr = pgparams.ipDstBaseNum + pgparams.ipDstVaryNum * varyIp

    local portSrcAddr = 
        band(pgparams.portSrcBase + pgparams.portSrcVary * varyPort, 0xffff)
    local portDstAddr = 
        band(pgparams.portDstBase + pgparams.portDstVary * varyPort, 0xffff)

    local pkt = buf:getUdpPacket()

    local ethSrcFlipped = rshift(bswap(ethSrc + 0ULL), 16)
    local ethDstFlipped = rshift(bswap(ethDst + 0ULL), 16)

    -- ETH mode
    pkt.eth:setType(ETHER_TYPE_IPv4)
    pkt.eth:setSrc(ethSrcFlipped)
    pkt.eth:setDst(ethDstFlipped)

    -- IP mod
    pkt.ip4:setLength(ipLength)
    pkt.ip4:setHeaderLength(IP_HEADER_LENGTH)
    pkt.ip4:setProtocol(17)
    pkt.ip4:setTTL(64)
    pkt.ip4:setSrc(ipSrcAddr)
    pkt.ip4:setDst(ipDstAddr)

    -- UDP mod
    pkt.udp:setLength(udpLength)
    pkt.udp:setSrcPort(portSrcAddr)
    pkt.udp:setDstPort(portDstAddr)

    -- Start of payload looks as follows:
    --
    -- |  Byte 0  |  Byte 4  |  Byte 8  |  Byte 12  |
    -- ----------------------------------------------
    -- |      timestamp      |  flowid  |  streamid |
    -- ----------------------------------------------
    --
    -- The timestamp is alredy set, so set flow and stream id.
    pkt.payload.uint32[2] = btxparams.flowid
    pkt.payload.uint32[3] = btxparams.streamid

    -- Fill the rest of the payload
    local payLength   = udpLength - UDP_HEADER_LENGTH
    local i           = 16             -- tstamp, flowid, streamid = 16 bytes
    local offset      = i              -- Start offset into payload bytes
    local l           = 0
    local l0          = pgparams.defaultPayloadSize
    local currSegData = TOTAL_HEADER_LENGTH + i

    while ((currSegData < MAX_SEG_LENGTH) and (payLength > 0)) do
        l = math.min(l0, math.floor(MAX_SEG_LENGTH - currSegData))
        l = math.min(l, payLength)

        -- Copy l bytes from the default payload to the actual payload
        local endIndex = i + l
        while i < endIndex do
            pkt.payload.uint8[i] = 
              string.byte(pgparams.defaultPayload, i - offset + 1) or 0
            i = i + 1
        end 
        payLength   = payLength - l
        currSegData = currSegData + l
    end
end

-- RX functionality -----------------------------------------------------------

-- @brief Drops the (received) rxpackets.
-- @param rxpackets The received packets to drop.
function simpleDrop(rxpackets) 
    rxpackets:freeAll()
end

-- Trafgen params -------------------------------------------------------------

-- @brief Prints out the paramers.
function params:print()
    local paramString = string.format(
      "\n+-------- Parameters ---------------------------------+"       ..
      "\n| Cores              : %30u |"                                 ..
      "\n| TX queues per core : %30u |"                                 ..
      "\n| RX queues per core : %30u |"                                 ..
      "\n| Total TX queues    : %30u |"                                 ..
      "\n| Portmask           : %30s |"                                 ..
      "\n| Flows per stream   : %30u |"                                 ..
      "\n| Number of streams  : %30u |"                                 ..
      "\n| Bursts per stream  : %30u |"                                 ..
      "\n| TX burst size      : %30u |"                                 ..
      "\n| RX burst size      : %30u |"                                 ..
      "\n| TX delta           : %30u |"                                 ..
      "\n| Total flows        : %30u |"                                 ..
      "\n| Packet size        : %30u |"                                 ..
      "\n| Using Imix size    : %30s |"                                 ..
      "\n| Timer period       : %30u |"                                 ..
      "\n| ETH src base       : %30s |"                                 ..
      "\n| ETH src vary       : %30s |"                                 ..
      "\n| ETH dst base       : %30s |"                                 ..
      "\n| ETH dst vary       : %30s |"                                 ..
      "\n| ETH stride         : %30s |"                                 ..
      "\n| IP src base        : %30s |"                                 ..
      "\n| IP src vary        : %30s |"                                 ..
      "\n| IP dst base        : %30s |"                                 ..
      "\n| IP dst vary        : %30s |"                                 ..
      "\n| IP stride          : %30s |"                                 ..
      "\n| PORT src base      : %30u |"                                 ..
      "\n| PORT src vary      : %30u |"                                 ..
      "\n| PORT dst base      : %30u |"                                 ..
      "\n| PORT dst vary      : %30u |"                                 ..
      "\n| PORT stride        : %30u |"                                 ..
      "\n| No RX descriptors  : %30u |"                                 ..
      "\n| No TX descriptors  : %30u |"                                 ..
      "\n| No ports           : %30u |"                                 ..
      "\n| Param display time : %30u |"                                 ..
      "\n+-----------------------------------------------------+\n"     ,
      self.cores                                                        ,
      self.txPortsPerCore                                               ,
      self.rxPortsPerCore                                               ,
      self.totalTxPorts                                                 ,
      self.portmask                                                     ,
      self.flowsPerStream                                               ,
      self.numberOfStreams                                              ,
      self.burstPerStream                                               ,
      self.txBurstSize                                                  ,
      self.rxBurstSize                                                  ,
      self.txDelta                                                      ,
      self.totalFlows                                                   ,
      self.packetSize                                                   ,
      tostring(self.mustImix)                                           ,
      self.timerPeriod                                                  ,
      self.ethSrcBase                                                   ,
      self.ethSrcVary                                                   ,
      self.ethDstBase                                                   ,
      self.ethDstVary                                                   ,
      self.ethStride                                                    ,
      self.ipSrcBase                                                    ,
      self.ipSrcVary                                                    ,
      self.ipDstBase                                                    ,
      self.ipDstVary                                                    ,
      self.ipStride                                                     ,
      self.portSrcBase                                                  ,
      self.portSrcVary                                                  ,
      self.portDstBase                                                  ,
      self.portDstVary                                                  ,
      self.portStride                                                   ,
      self.nbRxd                                                        ,
      self.nbTxd                                                        ,
      self.nbPorts                                                      ,
      self.paramDisplay / 1000
  )

  print(paramString)
end

-- Command line argument parsing ----------------------------------------------

-- Defines a table to specify which address have been converted
-- to the numeric representation for use with MoonGen.
local addressConversionMask = {
    ethSrcBase = false, 
    ethSrcVary = false,
    ethDstBase = false, 
    ethDstVary = false,
    ethStride  = false,
    ipSrcBase  = true ,
    ipSrcVary  = false,
    ipDstBase  = true ,
    ipDstVary  = false,
    ipStride   = false
}

-- @brief Prints the usage options for the traffic generation app.
function printUsage()
    local exampleUsage = string.format(
        "Usage is:\n Moongen packegen.lua <Optional Args> where:\n"       ..
        " Optional Args:\n\n"                                             ..
        "   --txd|-A DESCRIPTORS where\n"                                 ..
        "     DESCRIPTORS : Number of TX descriptors (default 1024)\n\n"  ..
        "   --rxd|-B DESCRIPTORS where\n"                                 ..
        "     DESCRIPTORS : Number of RX descriptors (default 1024)\n\n"  ..
        "   --dst-vary|-D MAC_VARY,IP_VARY,PORT_VARY where\n"             ..
        "     MAC_VARY  : Vary source mac (format a:b:c:d:e:f)\n"         ..
        "     IP_VARY   : Vary source ip  (format a.b.c.d)\n"             ..
        "     PORT_VARY : Vary port ip (format a (number))\n"             ..
        "     NOTE: comma separated list without spaces, example:\n"      ..
        "           00:00:00:00:a0:21,0.0.0.1,2\n\n"                      ..
        "   --src-vary|-S MAC_VARY,IP_VARY,PORT_VARY where\n"             ..
        "     MAC_VARY  : Vary source mac (format a:b:c:d:e:f)\n"         ..
        "     IP_VARY   : Vary source ip  (format a.b.c.d)\n"             ..
        "     PORT_VARY : Vary port ip (format a (number))\n"             ..
        "     NOTE: comma separated list without spaces, example:\n"      ..
        "           00:00:00:00:a0:21,0.0.0.1,2\n\n"                      ..
        "   --stats-period|-T PERIOD where\n"                             ..
        "     PERIOD Stats refresh period on each core, in seconds\n"     ..
        "     (default = 1, 0 = disable)\n"                               ..
        "     NOTE: The stats for each core are printed iteratively\n"    ..
        "           every PERIOD seconds, followed by a delay of\n"       ..
        "           PERIOD seconds before starting the iterative\n"       ..
        "           print process again.\n\n"                             ..
        "   --param-display|-a TIME where\n"                              ..
        "     TIME : Seconds to display params before running\n"          ..
        "            (default 3 seconds)\n\n"                             ..
        "   --cores|-c CORES where\n"                                     ..
        "     CORES : Number of cores to use (default 1)\n\n"             ..
        "   --tx-queues|-d TX_QUEUS where\n"                              ..
        "     TX_QUEUS : Total number of tx queues (default 1)\n\n"       ..
        "   --mac-stride|-g MAC_STRIDE where\n"                           ..
        "     MAC_STRIDE : MAC stride between streams (a:b:c:d:e:f)\n\n"  ..
        "   --help|-h Print usage\n\n"                                    ..
        "   --streams|-i NUM_STREAMS where\n"                             ..
        "     NUM_STREAMS : Number of streams (default 1)\n\n"            ..
        "   --bursts-per-stream|-j NUM_BURSTS where\n"                    ..
        "     NUM_BURSTS : Number of bursts per stream (default 1)\n\n"   ..
        "   --ip-stride|-k IP_STRIDE where\n"                             ..
        "     IP_STRIDE : IP stride between streams (A.B.C.D)\n\n"        ..
        "   --src-port|-m SRC_PORT where\n"                               ..
        "     SRC_PORT : Base source UDP port\n\n"                        ..
        "   --dst-port|-n DST_PORT where\n"                               ..
        "     DST_PORT : Base destination UDP port\n\n"                   ..
        "   --port-stride|-o PORT_STRIDE where\n"                         ..
        "     PORT_STRIDE : PORT stride between streams\n\n"              ..
        "   (All strides default to flows-per-stream)\n\n"                ..
        "   --portmask|-p PORTMASK where\n"                               ..
        "     PORTMASK : Hexadecimal port mask (default 0003)\n\n"        ..
        "   --queues-per-core|-q QUEUES where\n"                          ..
        "     QUEUES : Number of queues (ports) per core (default 1)\n"   ..
        "   (The default is for each core to have a tx and rx queue,\n"   ..
        "    currently only 1 tx queue per core is supported)\n\n"        ..
        "   --pps|-r RATE where\n"                                        ..
        "     RATE Packets per second rate to attempt.\n\n"               ..
        "   --rx-burst|-R RX_BURST_SIZE where\n"                          ..
        "     RX_BURST_SIZE : RX burst size (default 32)\n\n"             .. 
        "   --tx-burst|-t TX_BURST_SIZE where\n"                          ..
        "     TX_BURST_SIZE : TX burst size (default 32)\n\n"             ..
        "   --src-mac|-w SRC_MAC where\n"                                 ..
        "     SRC_MAC : Base SRC mac address (a:b:c:d:e:f)\n\n"           ..
        "   --dst-mac|-x DST_MAC where\n"                                 ..
        "     DST_MAC : Base DST mac adress (a:b:c:d:e:f)\n\n"            ..
        "   --flows-per-stream|-y NUM_FLOWS where\n"                      ..
        "     NUM_FLOWS : Number of flows per stream (default 2047)\n"    ..
        "     NOTE: Using more than 2047 fps decreases performance.\n"    ..
        "           To generate more flows, it's preferable to \n"        ..
        "           increase the number of streams\n\n"                   ..
        "   --pkt-size|-z PKT_SIZE where\n"                               ..
        "     PKT_SIZE : Packet size (0 for IMIX, default 64)\n\n"        
    )
    print(exampleUsage)
end

-- Parses the command line arguments.
-- @param params The default parameters to configure
-- @param ...    A table of the command line arguments
function parseArgs(params, ...)
    local command  = true  
    local args     = {...} 

    for i,v in ipairs(args) do 
        if type(v) == "string" then 
            if v == "--txd" or v == "-A" then 
                params.nbTxd = tonumber(args[i + 1])
            elseif v == "--rxd" or v == "-B" then 
                params.nbRxd = tonumber(args[i + 1])
            elseif v== "--vary-dst" or v == "-D" then 
                ethVar, ipVar, portVar =
                  args[i + 1]:match("([^,]+),([^,]+),([^,]+)")
                params.ethDstVary  = ethVar
                params.ipDstVary   = ipVar
                params.portDstVary = tonumber(portVar)

                addressConversionMask.ethSDstVary = true
                addressConversionMask.ipDstVary   = true
            elseif v == "--vary-src" or v == "-S" then 
                ethVar, ipVar, portVar =
                  args[i + 1]:match("([^,]+),([^,]+),([^,]+)")
                params.ethSrcVary  = ethVar
                params.ipSrcVary   = ipVar
                params.portSrcVary = tonumber(portVar)

                addressConversionMask.ethSrcVary = true
                addressConversionMask.ipSrcVary  = true
            elseif v == "--stats-period" or v == "-T" then 
                local period = tonumber(args[i + 1])
                if period < 0 or period > 86400 then 
                    print("Invalid stats refresh period")
                    return false
                end 
                params.timerPeriod = period
            elseif v == "--param-display" or v == "-a" then 
                local paramDisplay = tonumber(args[i + 1])
                if paramDisplay < 0 then 
                    print("Invalid param display time, using " ..
                          "default")
                else  
                    params.paramDisplay = paramDisplay * 1000
                end
            elseif v == "--cores" or v == "-c" then
                local cores = tonumber(args[i + 1])
                if cores < 1 then 
                    print("Invalid number of cores")
                    printUsage()
                    return false
                end
                params.cores = cores
            elseif v == "--tx-queues" or v == "-d" then 
                local totalTxPorts = args[i + 1]
                if totalTxPorts < 0 then 
                    print("Invalid number of tx queues")
                    printUsage()
                    return false
                else 
                    params.totalTxPorts = totalTxPorts 
                end
            elseif v == "--mac-stride" or v == "-g" then
                params.ethStride                = args[i + 1]
                addressConversionMask.ethStride = true
            elseif v == "--help" or v == "-h" then 
                printUsage()
                return false
            elseif v == "--streams" or v == "-i" then 
                local streams = tonumber(args[i + 1])
                if (streams < 0) then 
                    print("Invalid number of streams")
                    printUsage()
                    return false
                end
                params.numberOfStreams = streams
            elseif v == "--bursts-per-stream" or v == "-j" then
                local bursts = tonumber(args[i + 1])
                if (bursts < 0) then 
                    print("Invalid number of bursts per stream")
                    printUsage()
                    return false
                end 
                params.burstPerStream = bursts
            elseif v == "--ip-stride" or v == "-k" then 
                params.ipStride                = args[i + 1]
                addressConversionMask.ipStride = true
            elseif v == "--src-port" or v == "-m" then 
                params.portSrcBase = tonumber(args[i + 1])
            elseif v == "--dst-port" or v == "-n" then 
                params.portDstBase = tonumber(args[i + 1])
            elseif v == "--port-stride" or v == "-o" then 
                params.portStride = tonumber(args[i + 1])
            elseif v == "--portmask" or v == "-p" then 
                params.portmask = args[i + 1]
            elseif v == "--queues-per-core" or v == "-q" then 
                local qpc = tonumber(args[i + 1])
                  if qpc > MAX_RX_QUEUS_PER_CORE then
                    print("Invalid queues per core, the max is:",
                        MAX_RX_QUEUES_PER_CORE)
                    return false
                  end
                params.rxPortsPerCore = qpc
            elseif v == "--pps" or v == "-r" then 
                print(string.format("Using burst size of: %u, for txPps " 
                  .. "calculation. If this is not the txBurstSize you want, "
                  .. "use --tx-burst-size before --pps", params.txBurstSize))

                local txPps = tonumber(args[i + 1]) 
                local txDelta = math.floor(
                                    moongen:getCyclesFrequency() / txPps
                               ) * params.flowsPerStream * params.burstPerStream
                if txDelta < 0 then 
                    print("Invalid TX delta")
                    printUsage()
                    return false
                end
                params.txDelta = txDelta
            elseif v == "--rx-burst" or v == "-R" then 
                local rxBurst = tonumber(args[i + 1])
                if rxBurst < MIN_RX_BURST_SIZE or 
                   rxBurst > MAX_RX_BURST_SIZE then 
                      print("Invalid RX burst size")
                      printUsage()
                      return false
                end
                params.rxBurstSize = rxBurst
            elseif v == "--tx-burst" or v == "-t" then 
                local txBurst = tonumber(args[i + 1])
                if txBurst < MIN_TX_BURST_SIZE  or
                   txBurst > MAX_TX_BURST_SIZE then 
                      print("Invalid TX burst size")
                      printUsage()
                      return false
                end
                params.txBurstSize = txBurst
            elseif v == "--src-ip" or v == "-u" then 
                params.ipSrcBase                = args[i + 1]
                addressConversionMask.ipSrcBase = true
            elseif v == "--dst-ip" or v == "-v" then
                params.ipDstBase                = args[i + 1]
                addressConversionMask.ipDstBase = true
            elseif v == "--src-mac" or v == "-w" then 
                params.ethSrcBase                = args[i + 1]
                addressConversionMask.ethSrcBase = true
            elseif v == "--dst-mac" or v == "-x" then 
                params.ethDstBase                = args[i + 1]
                addressConversionMask.ethDstBase = true
            elseif v == "--flows-per-stream" or v == "-y" then 
                local fps = tonumber(args[i + 1])
                if fps < 0 then 
                    print("Invalid number of flows per stream")
                    printUsage()
                    return false
                end 
                params.flowsPerStream = fps
            elseif v == "--pkt-size" or v == "-z" then 
                local pktSize = tonumber(args[i + 1])
                if pktSize == 0 then 
                    params.mustImix   = true
                    params.packetSize = pktSize
                elseif pktSize < 64 or pktSize > 1514 then
                    print("Invalid packet size")
                    printUsage()
                    return false
                else
                    params.packetSize = pktSize + 4
                end
            else
                if command then 
                    print("Unkown command: ", v, "ignoring!")
                end
            end

            if command then command = false else command = true end
        end
    end   

    -- Convert all the numeric addresses to numeric ones
    convertAddressesToNumeric(params)

    -- Check that the strides are valid
    if params.ethStrideNum == 0 then 
        params.ethStrideNum = band(params.flowsPerStream, 0xffffffffffff)  
    end
    if params.ipStrideNum == 0 then 
        params.ipStrideNum = band(params.flowsPerStream, 0xffffffff)  
    end
    if params.portStride == 0 then 
        params.portStride = band(params.flowsPerStream, 0xffff) 
    end 

    params.totalFlows = params.numberOfStreams * params.flowsPerStream

    return true
end

-- @brief Converts string versions of addresses to numeroic ones
-- @param params The parameters to update the numeric addresses of.
function convertAddressesToNumeric(params) 
    -- MAC related-------------------------------------------------------------

    if addressConversionMask.ethSrcBase then 
        params.ethSrcBaseNum = parseMacAddress(params.ethSrcBase, true)
    end

    if addressConversionMask.ethDstBase then 
        params.ethDstBaseNum = parseMacAddress(params.ethDstBase, true)
    end

    if addressConversionMask.ethSrcVary then 
        params.ethSrcVaryNum = parseMacAddress(params.ethSrcVary, true)
    end

    if addressConversionMask.ethDstVary then 
        params.ethDstVaryNum = parseMacAddress(params.ethDstVary, true)
    end 

    if addressConversionMask.ethStride then 
        params.ethStrideNum = parseMacAddress(params.ethStride, true)
    end

    -- IP related -------------------------------------------------------------

    if addressConversionMask.ipSrcBase then 
        params.ipSrcBaseNum = parseIPAddress(params.ipSrcBase, true)
    end

    if addressConversionMask.ipDstBase then 
        params.ipDstBaseNum = parseIPAddress(params.ipDstBase, true)
    end

    if addressConversionMask.ipSrcVary then 
        params.ipSrcVaryNum = parseIPAddress(params.ipSrcVary, true)
    end

    if addressConversionMask.ipDstVary then 
        params.ipDstVaryNum = parseIPAddress(params.ipDstVary, true)
    end 

    if addressConversionMask.ipStride then 
        params.ipStrideNum = parseIPAddress(params.ipStride, true)
    end
end

-- Stats ----------------------------------------------------------------------

-- @brief Prints the statistics for a port on a core.
-- @param coreid The id of the core for which the stats are being printed.
-- @param portid The id of the port for which the stats are being printed.
function stats:print(coreid, portid)
  local statsString = string.format(
    "\n+------ Statistics for core %3u, port %3u ----------------------+"   ..
    "\n| Packets sent               : %32u |"                               ..
    "\n| Packet send rate           : %32.2f |"                             ..
    "\n| Packets received           : %32u |"                               ..
    "\n| Packet receive rate        : %32.2f |"                             ..
    "\n| Bytes sent                 : %32u |"                               ..
    "\n| Byte send rate             : %32.2f |"                             ..
    "\n| Bytes received             : %32u |"                               ..
    "\n| Byte receive rate          : %32.2f |"                             ..
    "\n| Packets dropped on send    : %32u |"                               ..
    "\n| Packets dropped on receive : %32u |"                               ..
    "\n| TX packets short           : %32u |"                               ..
    "\n| RX mean latency            : %32.10f |"                            ..
    "\n| RX mean2 latency           : %32.10f |"                            ..
    "\n+---------------------------------------------------------------+"   ,
    coreid                                                                  ,
    portid                                                                  ,
    self.txPackets                                                          ,
    (self.txPackets - self.prevTxPackets) / self.elapsedTime                ,
    self.rxPackets                                                          ,
    (self.rxPackets - self.prevRxPackets) / self.elapsedTime                ,
    self.txBytes                                                            ,
    (self.txBytes - self.prevTxBytes) / self.elapsedTime                    ,
    self.rxBytes                                                            ,
    (self.rxBytes - self.prevRxBytes) / self.elapsedTime		    ,
    self.txDropped                                                          ,
    self.rxDropped                                                          ,
    self.txShort                                                            ,
    self.rxMeanLatency                                                      ,
    self.rxM2Latency
  )
  
  print(statsString)
end

-- Utilities ------------------------------------------------------------------

-- @brief Converts a number to a hex string representation.
-- @param num The number to convert to hex.
function num2hex(num)
    local hexstr = '0123456789abcdef'
    local s      = ''
    while num > 0 do
        local mod = math.fmod(num, 16)
        s         = string.sub(hexstr, mod + 1, mod + 1) .. s
        num       = math.floor(num / 16)
    end
    if s == '' then s = '0' end
    return s
end

-- Converts a mac address in number format (a long) to a string based mac
-- address of the form: a:b:c:d:e:f
-- @param mac The mac address to convert
function convertMacNumberToString(mac) 
    local macArray = {}
    for i = 6, 1, -1 do
        macArray[i] = bit.band(mac, 0xff)
        mac         = bit.rshift(mac, 8)
    end
    local macString = string.format("%u:%u:%u:%u:%u:%u",
      macArray[1], macArray[2], macArray[3],
      macArray[4], macArray[5], macArray[6]
    )
    return macString
end

-- @brief Generates a random number between 1 - 120 for the IMIX.
function imixSize() 
    math.randomseed(os.time())
    -- Might need to pop some random numbers here if these aren't random

    local rnum = math.random(120);
    if rnum < 10 then         -- 1 in 12
        return 1518
    elseif rnum < 50 then     -- 4 in 12
        return 574
    else                      -- 7 in 12
        return 68     
    end
end

-- Deep copies a table, and returns the copy.
-- @param orig The original table to copy.
function deepCopy(orig)
    local origType = type(orig)
    local copy    

    if origType == 'table' then
        copy = {}
        for k,v in next, orig, nil do
            copy[deepCopy(k)] = deepCopy(v)
        end
        setmetatable(copy, deepCopy(getmetatable(orig)))
    else -- simple type
        copy = orig
    end
    return copy
end
