local selfPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "/"

local module = {}

return require(selfPath .. "sc")