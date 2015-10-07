local utils = require "utils.utils"

local mod = {}
mod.__index = mod

local texHdr = [[
\documentclass{article}
\usepackage{multirow}
\usepackage{graphicx}
\usepackage{longtable,tabu}
\usepackage[margin=1in]{geometry}
\renewcommand{\thesubsection}{\arabic{subsection}}
\begin{document}
\section*{RFC 2544 Test Report}
]]

local vspaceTex = [[
\vspace*{0.5cm}
\newline
]]

local imgTex = [[
\begin{center}
\includegraphics{##IMG##}
\end{center}
]]

local generalInfoTex = [[
\subsection{General Test Information}
\begin{tabu} to \textwidth{lX}
Device Under Test: & ##DUT_NAME## \\
Operating System: & ##OS_NAME## \\
Date: & ##DATE##\\
\end{tabu}
]]

local throughputInfoTex = [[
\subsection{Throughput}\begin{tabu} to \textwidth{lX}
Test Duration: & ##DURATION## \\
Maximal Loss Rate: & ##MAXLOSS## \\
Accuracy: & ##ACCURACY## \\
\end{tabu}
]]

local latencyInfoTex = [[
\subsection{Latency}\begin{tabu} to \textwidth{lX}
Test Duration: & ##DURATION## \\
\end{tabu}
]]

local framelossInfoTex = [[
\subsection{Frame loss rate}\begin{tabu} to \textwidth{lX}
Test Duration: & ##DURATION## \\
\end{tabu}
]]

local btbInfoTex = [[
\subsection{Back-to-back frames}\begin{tabu} to \textwidth{lX}
Test Duration: & ##DURATION## \\
Accuracy: & ##ACCURACY## \\
Rate: & ##RATE## \\
\end{tabu}
]]

function mod.new(filename)    
    local self = setmetatable({}, mod)
    
    self.filename = filename
    
    self.throughput = {}
    self.latency = {}
    self.frameloss = {}
    self.btb = {}
    
    return self
end

function mod:addThroughput(result, duration, mlr, accuracy)
    self.throughput.duration = duration
    self.throughput.mlr = mlr
    self.throughput.accuracy = accuracy
    table.insert(self.throughput, {k = result[1].frameSize, v = result})
end

function mod:addLatency(result, duration)
    self.latency.duration = duration
    table.insert(self.latency, {k = result.frameSize, v = result})
end

function mod:addFrameloss(result, duration)
    self.frameloss.duration = duration
    table.insert(self.frameloss, {k = result[1].size, v = result})    
end

function mod:addBackToBack(result, duration, accuracy, rate)
    self.btb.duration = duration
    self.btb.accuracy = accuracy
    self.btb.rate = rate
    table.insert(self.btb, {k = result.frameSize, v = result})
end


function mod:writeGeneralInfo(file)
    local tex = generalInfoTex
    tex = tex:gsub("##DUT_NAME##", utils.getDeviceName())
    tex = tex:gsub("##OS_NAME##", utils.getDeviceOS())
    tex = tex:gsub("##DATE##", os.date("%F"))
    file:write(tex)
end

function mod:writeThroughput(file)
    local tex = throughputInfoTex
    tex = tex:gsub("##DURATION##", string.format("%d s", self.throughput.duration))
    tex = tex:gsub("##MAXLOSS##", string.format("%.3f \\%%%%", self.throughput.mlr * 100))
    tex = tex:gsub("##ACCURACY##", string.format("%d Mbps", self.throughput.accuracy))
    file:write(tex)
    file:write(vspaceTex)
    file:write("\\begin{longtabu} to \\textwidth {X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]} \\hline\n")
    file:write("Frame Size (bytes) & Iteration & Total Tx Frames & Total Rx Frames & Throughput (Mpps) & Throughput (Mbps)\\\\ \\hline\n")
    table.sort(self.throughput, function(e1, e2) return e1.k < e2.k end)
    for _, p in ipairs(self.throughput) do
        local multirow = #p.v > 1
        if multirow then
            -- multirow for 1 column does not work well
            file:write(string.format("\\multirow{%d}{*}{%d}", #p.v, p.k))
        end
        
        for i, r in ipairs(p.v) do
            if not multirow then
                file:write(r.frameSize)
            end
            file:write(string.format(" & %d & %d & %d & %.3f & %.3f\\\\\n", i , r.spkts, r.rpkts, r.mpps, r.mpps * 8 * (r.frameSize + 20)))
        end
    end
    file:write("\\hline\n\\end{longtabu}\n")
    local img = imgTex:gsub("##IMG##", "plot_throughput_mpps") 
    file:write(img)
    file:write("\\newpage\n")
end

function mod:writeLatency(file)
    local tex = latencyInfoTex
    tex = tex:gsub("##DURATION##", string.format("%d s", self.latency.duration))
    file:write(tex)
    file:write(vspaceTex)
    file:write("\\begin{longtabu} to \\textwidth {X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]X[4,r,m]} \\hline\n")
    file:write("Frame Size (bytes) & Throughput (Mpps) & Latency Min ($\\mu$s)& Latency Avg ($\\mu$s)& Latency Max ($\\mu$s)& \\\\ \\hline\n")
    for _, p in ipairs(self.latency) do
        local histo = p.v
        histo:calc()
        local n = #histo.sortedHisto
        file:write(string.format("%d & %.3f & %.1f & %.1f & %.1f & \\includegraphics[width=\\linewidth]{plot_latency_histo_%d} \\\\\n", p.k, histo.rate, histo.sortedHisto[1].k, histo.avg, histo.sortedHisto[n].k ,p.k))
    end
    file:write("\\hline\n\\end{longtabu}\n\\newpage\n")
end

function mod:writeFrameloss(file)
    local tex = framelossInfoTex
    tex = tex:gsub("##DURATION##", string.format("%d s", self.frameloss.duration))
    file:write(tex)
    file:write(vspaceTex)
    file:write("\\begin{longtabu} to \\textwidth {X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]} \\hline\n")
    file:write("Frame Size (bytes) & Load (\\%) &  Total Tx Frames & Total Rx Frames & Total Frames Lost  & Frame Loss (\\%) \\\\ \\hline\n")
    for _, p in ipairs(self.frameloss) do
        local n = #p.v
        print(p.k, n)
        file:write(string.format("\\multirow{%d}{*}{%d}", n, p.k))
        for _, r in ipairs(p.v) do
            file:write(string.format(" & %.1f & %d & %d & %d & %.4f \\\\ \n", r.multi * 100, r.spkts, r.rpkts, (r.spkts - r.rpkts), (r.spkts - r.rpkts) / (r.spkts) * 100))
        end
        file:write("\\hline\n")
    end
    file:write("\\end{longtabu}")
    local img = imgTex:gsub("##IMG##", "plot_frameloss_percent") 
    file:write(img)
end

function mod:writeBackToBack(file)    
    local tex = btbInfoTex
    tex = tex:gsub("##DURATION##", string.format("%d s", self.btb.duration))
    tex = tex:gsub("##ACCURACY##", string.format("%d packets", self.btb.accuracy))
    tex = tex:gsub("##RATE##", string.format("%d Mbps", self.btb.rate))
    file:write(tex)
    file:write(vspaceTex)
    file:write("\\begin{longtabu} to \\textwidth {X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]X[-1,r,m]} \\hline\n")
    file:write("Frame Size (bytes) & Burst size min & Burst size avg & Burst size max & Theoretical maximum\\\\ \\hline\n")
    for _, p in ipairs(self.btb) do
        local sum, avg = 0, 0
        local min, max = math.huge, -math.huge
        for _, r in ipairs(p.v) do
            min, max = math.min(min, r), math.max(max, r)
            sum = sum + r
        end
        avg = sum / #p.v
        file:write(string.format("%d & %d & %.1f & %d & %d\\\\\n", p.k, min, avg, max, math.ceil(self.btb.rate / (p.k + 20) / 8 * self.btb.duration * 10^6)))
    end
    file:write("\\hline\n\\end{longtabu}\n")
    local img = imgTex:gsub("##IMG##", "plot_backtoback") 
    file:write(img)
end

function mod:finalize()
    local texFile = io.open(self.filename, "w")
    texFile:write(texHdr)
    
    self:writeGeneralInfo(texFile)    
    
    if #self.throughput > 0 then
        self:writeThroughput(texFile)
    end
    
    if #self.latency > 0 then
        self:writeLatency(texFile)        
    end
    
    if #self.frameloss > 0 then
        self:writeFrameloss(texFile)        
    end
    
    if #self.btb > 0 then
        self:writeBackToBack(texFile)        
    end
    texFile:write("\\end{document}")
    texFile:close()
end

return mod
