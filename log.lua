local module = {}

module.log = {}
module.log.__index = module.log

function module.new(name) -- creates a new Log file
    local self = setmetatable({}, module.log)

    self.fileName = name .. ".log"

    self.file = love.filesystem.newFile(self.fileName)

    if not love.filesystem.getInfo(self.fileName) then
        self.file:open("w")
        self.file:write("Log created in [" .. os.date() .. "]\n")
        self.file:close()
    else
        self.file:open("a")
        self.file:write("Log opened in [" .. os.date() .. "]\n")
        self.file:close()
    end

    self.data = {}

    return self
end

function module.log:dump() -- dumps table into log
    if #self.data < 1 then return end

    self.file:open("a")
    for i, str in ipairs(self.data) do
        self.file:write("[" .. os.date() .. "]>" .. str)
    end
    self.file:close()

    self.data = {}
end

function module.log:WARNING(format, ...)
    self:instaLog("<WARNING>" .. format, ...)
end

function module.log:NONFATAL_ERROR(format, ...)
    self:instaLog("<NONFATAL_ERROR>" .. format, ...)
end

function module.log:FATAL_ERROR(format, ...)
    self:instaLog("<FATAL_ERROR>" .. format, ...)
end

function module.log:write(format, ...) -- store logs in a table so that it stores everything at once
    local str = string.format(format, ...) .. "\n"
    table.insert(self.data, str)
end

function module.log:instaLog(format, ...) -- writes to the Instant log, may cause performance issues. Use only for critical parts
    local str = string.format(format, ...) .. "\n"
    self.file:open("a")
    self.file:write("[" .. os.date() .. "]>" .. str)
    self.file:close()
end

return module