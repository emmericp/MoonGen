
local tikz = {}
tikz.__index = tikz

local strStart = [[
\documentclass{standalone}
\usepackage{pgfplots}
\pgfplotsset{compat=newest}

\begin{document}
\begin{tikzpicture}
\begin{axis}]]
local strEnd = [[
\end{axis}
\end{tikzpicture}
\end{document}
]]

function escapeString(str)
   str = str:gsub("([%%\\%{%}#&_%^~])", "\\%1")
   str = str:gsub("\\\\", "\\textbackslash{}")
   str = str:gsub("\\^", "\\textasciicircum{}")
   return str
end

function tikz.new(filename, options)
    local self = setmetatable({}, tikz)
    self.file = io.open(filename, "w")
    self.plot = false
    
    self.file:write(strStart)
    if options then
--        self.file:write("[")
--        for k, v in pairs(options) do
--            if type(v) == "string" then v = escapeString(v) end
--            self.file:write(k .. "={" .. v .. "},")
--        end
--        self.file:write("]\n")
        self.file:write("[" .. options .. "]\n")
    else
        self.file:write("\n")
    end
    return self
end

function tikz:startPlot(options)
    local file = self.file
    file:write("    \\addplot")
    if options then
--        self.file:write("[")
--        for k, v in pairs(options) do
--            if type(v) == "string" then v = escapeString(v) end
--            self.file:write(k .. "={" .. v .. "},")
--        end
--        self.file:write("]\n")
        self.file:write("[" .. options .. "]")
    end
    file:write(" coordinates {\n")
    self.plot = true
end

function tikz:addPoint(x, y)
    if not self.plot then
        error("cannot add pair without plot")
    end
    self.file:write("        (" .. x .. ", " .. y .. ")\n")
end

function tikz:endPlot(legend)
    self.plot = false
    if legend then
        self.file:write("    };" .. "\\addlegendentry {" .. legend .. "}\n")
    else
        self.file:write("    };\n")
    end
end

function tikz:finalize(legend)
    if self.plot then
        self:endPlot(legend)
    end
    self.file:write(strEnd)
    self.file:close()
end

return tikz