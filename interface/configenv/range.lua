return function(env)

	function env.range(start, limit, step)
		step = step or 1

		if not limit then
			return function()
				local v = start
				start = start + step
				return v
			end
		end

		local val = start
		return function()
			local v = val

			val = val + step
			if val > limit then
				val = start
			end

			return v
		end
	end

	function env.list(tbl)
		local index, len = 1, #tbl
		return function()
			local v = tbl[index]

			index = index + 1
			if index > len then
				index = 1
			end

			return v
		end
	end

end
