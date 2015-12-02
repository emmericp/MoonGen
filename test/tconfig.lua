local ports 	= {14,15}
local cpairs	= {{14,15}}

local tconfig = {}
	function tconfig.ports()
		return ports
	end

	function tconfig.pairs()
		return cpairs
	end

return tconfig
