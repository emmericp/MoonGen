
------
---- Color Codes
------

local colorCode = {
	black	= "0;30",
	red		= "0;31",
	bred 	= "1;31",
	green	= "0;32",
	yellow	= "1;33",
	blue	= "0;34",
	white 	= "1;37",
	none	= "0"
}

function getColorCode(color)
	color = colorCode[color] or colorCode["none"]
	return "\027[" .. color .. "m"
end

------
---- Colorized String
------

function getColorizedString(str, color)
	return getColorCode(color)  .. str .. getColorCode()
end

function red(str, ...)
	return getColorizedString(str:format(...), "red")
end

function bred(str, ...)
	return getColorizedString(str:format(...), "bred")
end

function yellow(str, ...)
	return getColorizedString(str:format(...), "yellow")
end

function green(str, ...)
	return getColorizedString(str:format(...), "green")
end

function white(str, ...)
	return getColorizedString(str:format(...), "white")
end
