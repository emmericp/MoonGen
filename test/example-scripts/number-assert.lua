local assert = require "luassert"
local say = require "say"

function in_relative_range(state, args)
	local actual = args[1]
	local expected = args[2]
	local range = args[3] / 100
	return actual >= expected * (1 - range) and actual <= expected * (1 + range)
end

say:set_namespace("en")
say:set("assertion.in_relative_range.fail", "Value %s not in range %s +- %s%%")

assert:register("assertion", "rel_range", in_relative_range, "assertion.in_relative_range.fail")
