local ports 	= {7,8,11,12,13,14}
local cpairs	= {{7,11},{8,12},{13,14}}

local tconfig = {}
	function tconfig.ports()
		return ports
	end

	function tconfig.pairs()
		return cpairs
	end

return tconfig
