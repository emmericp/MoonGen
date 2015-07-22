package.path = package.path .. "scripts/?.lua;../scripts/?.lua;"

if master == nil then
	master = "dummy"
end

local dpdk          = require "dpdk"
local device        = require "device"
local arp           = require "proto.arp"

local throughput    = require "benchmarks.throughput"
local latency       = require "benchmarks.latency"
local frameloss     = require "benchmarks.frameloss"
local backtoback    = require "benchmarks.backtoback"
local utils         = require "utils.utils"

local conf          = require "config"

local FRAME_SIZES   = {64, 128, 256, 512, 1024, 1280, 1518}

local usageString = [[

    --txport <txport> 
    --rxport <rxport> 
    
    --rths <throughput rate threshold> 
    --mlr <max throuput loss rate>
    
    --bths <back-to-back frame threshold>
    
    --duration <single test duration>
    --iterations <amount of test iterations>    
    
    --din <DuT in interface name>
    --dout <DuT out iterface name>
    --dskip <skip DuT configuration>
    
    --asksshpass <true|false> [ask at beginning for SSH password]
    --sshpass <SSH password>
    --sshuser <SSH user>
    --sshport <SSH port>
    --asksnmpcomm <true|false> [ask at beginning for SNMP community string]
    --snmpcomm <SNMP community string>
    --host <mgmt host name of the DuT>
]]

local date = os.date("%F_%H-%M")

function log(file, msg, linebreak)
    print(msg)
    file:write(msg)
    if linebreak then
        file:write("\n")
    end
end

function master()
    local arguments = utils.parseArguments(arg)
    local txPort, rxPort = arguments.txport, arguments.rxport
    if not txPort or not rxPort then
        return print("usage: " .. usageString)
    end
    
    local rateThreshold = arguments.rths or 100
    local btbThreshold = arguments.bths or 100
    local duration = arguments.duration or 10
    local maxLossRate = arguments.mlr or 0.001
    local dskip = arguments.dskip
    local numIterations = arguments.iterations
    
    if type(arguments.sshpass) == "string" then
        conf.setSSHPass(arguments.sshpass)
    elseif arguments.asksshpass == "true" then
        io.write("password: ")
        conf.setSSHPass(io.read())
    end
    if type(arguments.sshuser) == "string" then
        conf.setSSHUser(arguments.sshuser)
    end
    if type(arguments.sshport) == "string" then
        conf.setSSHPort(tonumber(arguments.sshport))
    elseif type(arguments.sshport) == "number" then
        conf.setSSHPort(arguments.sshport)
    end
    
    if type(arguments.snmpcomm) == "string" then
        conf.setSNMPComm(arguments.snmpcomm)
    elseif arguments.asksnmpcomm == "true" then
        io.write("snmp community: ")
        conf.setSSHPass(io.read())
    end
    
    if type(arguments.host) == "string" then
        conf.setHost(arguments.host)
    end
    
    local dut = {
        ifIn = arguments.din,
        ifOut = arguments.dout
    }
    
    local rxDev, txDev
    if txPort == rxPort then
        -- sending and receiving from the same port
        txDev = device.config({port = txPort, rxQueues = 3, txQueues = 5})
        rxDev = txDev
    else
        -- two different ports, different configuration
        txDev = device.config({port = txPort, rxQueues = 2, txQueues = 5})
        rxDev = device.config({port = rxPort, rxQueues = 3, txQueues = 3})
    end
    device.waitForLinks()
    
    -- launch background arp table task
    if txPort == rxPort then 
        dpdk.launchLua(arp.arpTask, {
            { 
                txQueue = txDev:getTxQueue(0),
                rxQueue = txDev:getRxQueue(1),
                ips = {"198.18.1.2", "198.19.1.2"}
            }
        })
    else
        dpdk.launchLua(arp.arpTask, {
            {
                txQueue = txDev:getTxQueue(0),
                rxQueue = txDev:getRxQueue(1),
                ips = {"198.18.1.2"}
            },
            {
                txQueue = rxDev:getTxQueue(0),
                rxQueue = rxDev:getRxQueue(1),
                ips = {"198.19.1.2", "198.18.1.1"}
            }
        })
    end
    
    local results = {}
    
    local thBench = throughput.benchmark()
    thBench:init({
        txQueues = {txDev:getTxQueue(1), txDev:getTxQueue(2), txDev:getTxQueue(3)},
        rxQueues = {rxDev:getRxQueue(0)}, 
        duration = duration, 
        rateThreshold = rateThreshold,
        maxLossRate = maxLossRate,
        skipConf = dskip,
        dut = dut,
        numIterations = numIterations,
    })
    local rates = {}
    local file = io.open("results_throughput_" .. date, "w")
    log(file, thBench:getCSVHeader(), true)
    for _, frameSize in ipairs(FRAME_SIZES) do
        local result, avgRate = thBench:bench(frameSize)
        rates[frameSize] = avgRate
        table.insert(results, result)
        -- save and report results
        log(file, thBench:resultToCSV(result), true)
    end
    thBench:toTikz("plot_throughput_" .. date, unpack(results))
    file:close()
    
    results = {}
    local rates = {[64]=4.4294859, [128]=4.2199164,[256]=4.3201431, [512]=2.3495472,[1024]=1.1972835,[1280]=0.9615123,[1518]=0.8127189}
    local latBench = latency.benchmark()
    latBench:init({
        txQueues = {txDev:getTxQueue(1), txDev:getTxQueue(2), txDev:getTxQueue(3), txDev:getTxQueue(4)},
        -- different receiving queue, for timestamping filter
        rxQueues = {rxDev:getRxQueue(2)}, 
        duration = duration,
        skipConf = dskip,
        dut = dut,
    })
    
    file = io.open("results_latency_" .. date, "w")
    log(file, latBench:getCSVHeader(), true)
    for _, frameSize in ipairs(FRAME_SIZES) do
        local result = latBench:bench(frameSize, math.ceil(rates[frameSize] * (frameSize + 20) * 8))
        -- save and report results        
        table.insert(results, result)
        log(file, latBench:resultToCSV(result), true)
    end
    latBench:toTikz("plot_latency_" .. date, unpack(results))
    file:close()
    
    results = {}
    local flBench = frameloss.benchmark()
    flBench:init({
        txQueues = {txDev:getTxQueue(1), txDev:getTxQueue(2), txDev:getTxQueue(3)},
        rxQueues = {rxDev:getRxQueue(0)}, 
        duration = duration,
        granularity = 0.05,
        skipConf = dskip,
        dut = dut,
    })
    file = io.open("results_frameloss_" .. date, "w")
    log(file, flBench:getCSVHeader(), true)
    for _, frameSize in ipairs(FRAME_SIZES) do
        local result = flBench:bench(frameSize)
        -- save and report results
        table.insert(results, result)
        log(file, flBench:resultToCSV(result), true)
    end
    latBench:toTikz("plot_frameloss_" .. date, unpack(results))
    file:close()
    
    results = {}
    local btbBench = backtoback.benchmark()
    btbBench:init({
        txQueues = {txDev:getTxQueue(1), txDev:getTxQueue(2), txDev:getTxQueue(3)},
        rxQueues = {rxDev:getRxQueue(0)},
        granularity = btbThreshold,
        skipConf = dskip,
        numIterations = numIterations,
        dut = dut,
    })
    file = io.open("results_backtoback_" .. date, "w")
    log(file, btbBench:getCSVHeader(), true)
    for _, frameSize in ipairs(FRAME_SIZES) do
        local result = btbBench:bench(frameSize)
        -- save and report results
        table.insert(results, result)
        log(file, btbBench:resultToCSV(result), true)
    end
    latBench:toTikz("plot_backtoback_" .. date, unpack(results))
    file:close()
    
end
