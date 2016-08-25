---------------------------------
--- @file colors.lua
--- @brief Color Codes for colorized strings.
--- Includes:
--- - Color Codes
--- - Getter to colorize a string (supports formatting)
---------------------------------

---------------------------------------------
---- Color Codes
---------------------------------------------

local mod = {}

--- Table with color codes
local colorCode = {
	black 	= "0;30",
	dgrey 	= "1;30",
	red 	= "0;31",
	bred 	= "1;31",
	green 	= "0;32",
	bgreen 	= "1;32",
	brown 	= "0;33",
	yellow 	= "1;33",
	blue 	= "0;34",
	bblue 	= "1;34",
	dpurple = "0;35",
	bpurple = "1;35",
	dcyan 	= "0;36",
	cyan 	= "1;36",
	bgrey 	= "0;37",
	white 	= "1;37",
	none 	= "0"
}

mod.colorPallet = { 'blue', 'bgreen', 'dpurple', 'bred', 'brown', 'cyan', 'green', 'yellow', 'red' }

--- Get an escape sequence for one particular color.
--- @param color Color as string. See colorCode for possible colors. Default is no color (none).
--- 			 Color as number. Used as index for the color pallet.
--- @return Escape sequence as string
function getColorCode(color)
	if type(color) == "number" then
		color = colorCode[mod.colorPallet[color % #mod.colorPallet]]
	else
		color = colorCode[color] or colorCode["none"]
	end
	return "\027[" .. color .. "m"
end

---------------------------------------------
---- Colorized String
---------------------------------------------

--- Colorizes a string. No formatting supported.
--- @param str The string to be colorized.
--- @param color The color to be used.
--- @return The colorized string.
function getColorizedString(str, color)
	return getColorCode(color)  .. str .. getColorCode()
end

--- Colorize a string red.
--- @param str The string to be colorized.
--- @param args Formatting arguments
--- @return The colorized string.
function red(str, ...)
	return getColorizedString(str:format(...), "red")
end

--- Colorize a string bright red.
--- @param str The string to be colorized.
--- @param args Formatting arguments
--- @return The colorized string.
function bred(str, ...)
	return getColorizedString(str:format(...), "bred")
end

--- Colorize a string yellow.
--- @param str The string to be colorized.
--- @param args Formatting arguments
--- @return The colorized string.
function yellow(str, ...)
	return getColorizedString(str:format(...), "yellow")
end

--- Colorize a string green.
--- @param str The string to be colorized.
--- @param args Formatting arguments
--- @return The colorized string.
function green(str, ...)
	return getColorizedString(str:format(...), "green")
end

--- Colorize a string white.
--- @param str The string to be colorized.
--- @param args Formatting arguments
--- @return The colorized string.
function white(str, ...)
	return getColorizedString(str:format(...), "white")
end

return mod
