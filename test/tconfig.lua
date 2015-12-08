- Available local ports for testing -
local ports 	= {14,15}

- Available directly connected ports -
local cpairs	= {{14,15}}

- Threshold to which a card is considered "fully operational" -
local threshold = 0.75

local tconfig = {}
	function tconfig.ports()
		return ports
	end

	function tconfig.pairs()
		return cpairs
	end

	function tconfig.threshold()
		return threshold
	end
return tconfig
