local module = {}

module.NO_INFO = 0

module.CLIENT_DISCONNECT = 1
module.SERVER_DISCONNECT = 2
module.CLIENT_TIMEOUT = 3
module.SERVER_TIMEOUT = 4

module.INVALID_PASSWORD = 10
module.INVALID_LOGIN = 11

local selfPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"

module.json = require(selfPath .. "json")
module.log = require(selfPath .. "log")
module.base64 = require(selfPath .. "base64")
module.enet = require("enet")

local bit = require("bit")

local function ror(x, n)
    return bit.bor(bit.rshift(x, n), bit.lshift(x, 8 - n)) % 256
end

local function rol(x, n)
    return bit.bor(bit.lshift(x, n), bit.rshift(x, 8 - n)) % 256
end

local function encrypt(text, key)
    text = module.base64.encode(text)

    local sum = key
    for i = 1, #text do
        sum = sum + string.byte(text, i)
    end
    local shift = sum % 8

    local res = {}
    for i = 1, #text do
        local c = string.byte(text, i)
        table.insert(res, string.char(ror(c, shift)))
    end

    return module.base64.encode(string.char(shift) .. table.concat(res))
end

local function decrypt(text, key)
    text = module.base64.decode(text)
    local shift = string.byte(text, 1)
    text = text:sub(2)

    local res = {}
    for i = 1, #text do
        local c = string.byte(text, i)
        table.insert(res, string.char(rol(c, shift)))
    end
    return module.base64.decode(table.concat(res))
end

module.defaultPeerCount = 64
module.defaultChannelCount = 1
module.defaultInBandWidth = 0
module.defaultOutBandWidth = 0
module.defaultMaxTimeout = 256

module.new = {}

------------------------------------------------
-- PACKAGE
------------------------------------------------

local package = {}
package.__index = package

function module.new.package(data, events)
    local self = setmetatable({}, package)
    self.info = {
        data = data,
        timeSent = os.time(),
    }
    if events then
        self.info.events = events
        self.info.isEvent = true
    end
    return self
end

function package:validate()
    return type(self.info) == "table"
       and (type(self.info.data) == "table" or type(self.info.data) == "string")
       and type(self.info.timeSent) == "number"
end

function module.new.assembly(str)
    local tables = module.json.decode(str)

    if not (type(tables.info) == "table"
        and (type(tables.info.data) == "table" or type(tables.info.data) == "string")
        and type(tables.info.timeSent) == "number") then
        return nil
    end

    local self = setmetatable({}, package)
    self.info = {
        data = tables.info.data,
        timeSent = tables.info.timeSent,
    }

    if tables.info.events then
        self.info.events = tables.info.events
    end

    if not self:validate() then
        return nil
    end

    return self
end

------------------------------------------------
-- SERVER
------------------------------------------------

local server = {}
server.__index = server

function module.new.server(ip, port, name, password, log)
    local self = setmetatable({}, server)

    self.name = name or tostring(math.random(0, 999))
    self.password = password or ""
    self.ip = ip or "*"
    
    self.port = port or "0"
    self.adress = self.ip .. ":" .. self.port

    self.maxTimeout = module.defaultMaxTimeout
    self.clients = {}

    self.callbacks = {
        clientConnected = function(peer, clientData, index) print("client " .. clientData.name .. " connected") end,
        clientMessage = function(peer, clientData, index, data) print("message from " .. clientData.name .. ":", data) end,
        clientDisconnected = function(peer, clientData, index, data) print("client " .. clientData.name .. " disconnected '" .. data .. "'") end
    }

    self.host = module.enet.host_create(self.adress,
        module.defaultPeerCount,
        module.defaultChannelCount,
        module.defaultInBandWidth,
        module.defaultOutBandWidth
    )

    self.logDump = 0

    self.events = {}

    if log then
        self.log = module.log.new(self.name)

        self.log:instaLog("server '%s' was created successfully\n\n%s", self.name ,module.inspect(self))
    end

    return self
end

function server:update(dt)
    if self.log then
        self.logDump = self.logDump + dt

        if self.logDump >= 1 then
            self.log:dump()
            self.logDump = 0
        end
    end

    local event = self.host:service(50)
    while event do
        local peer = event.peer
        local data = event.data

        if event.type == "connect" then
            peer:timeout(5, 3000, 5000)
            self.clients[tostring(peer:index())] = {
                name = nil,
                index = peer:index(),
                ping = peer:round_trip_time()
            }
            

        elseif event.type == "receive" then
            if not self.clients[tostring(peer:index())].name then
                if data then
                    data = module.json.decode(data)
                    local ok = true

                    if not data.data.name or not data.data.password or not data.data.key then
                        peer:disconnect_now(module.INVALID_LOGIN)
                        ok = false
                    end

                    if data.data.password ~= self.password then
                        peer:disconnect_now(module.INVALID_PASSWORD)
                        ok = false
                    end

                    if ok then
                        
                        self.clients[tostring(peer:index())].name = data.data.name
                        self.clients[tostring(peer:index())].password = data.data.password
                        self.clients[tostring(peer:index())].key = data.data.key
                        self.callbacks.clientConnected(peer, self.clients[tostring(peer:index())], peer:index())
                    end
                end
            else
                data = decrypt(data, self.clients[tostring(peer:index())].key)
                if data then
                    data = module.json.decode(data)
                end

                local cli = self.clients[tostring(peer:index())]
                cli.ping = peer:round_trip_time()
                self.callbacks.clientMessage(peer, self.clients[tostring(peer:index())], peer:index(), data)
            end
        elseif event.type == "disconnect" then
            self.callbacks.clientDisconnected(peer, self.clients[tostring(peer:index())], peer:index(), data)
            self.clients[tostring(peer:index())] = nil
        end

        event = self.host:service()
    end

    if #self.events ~= 0 then
        self:broadcast("No Data", self.events)
        self.events = {}
    end
end

function server:newEvent(data)
    table.insert(self.events, data)
end

function server:sendInfo(peer, data, events)
    local pkg = module.new.package(data, events)
    local str = module.json.encode(pkg.info)
    self:sendRaw(peer, str)
end

function server:sendRaw(peer, data)
    if self.clients[tostring(peer:index())].key then
        data = encrypt(data, self.clients[tostring(peer:index())].key)
    end
    peer:send(data)
end

function server:broadcast(data, events)
    for _, cli in pairs(self.clients) do
        local peer = self.host:get_peer(cli.index)
        if peer then self:sendInfo(peer, data, events) end
    end
end

------------------------------------------------
-- CLIENT
------------------------------------------------

local client = {}
client.__index = client

function module.new.client(name)
    local self = setmetatable({}, client)
    self.name = name or "client_" .. tostring(math.random(0,9999))
    self.connected = false

    self.callbacks = {
        connected = function(peer) end,
        message = function(peer, data) end,
        disconnected = function(peer, data) end,
        event = function(peer, events) end
    }

    return self
end

function client:connect(ip, port, password, name)
    self.host = module.enet.host_create()
    self.server = self.host:connect(ip .. ":" .. port)
    self.name = name
    self.password = password

    if not password or not name then
        error()
    end

    self.__nameSend = false
end

function client:update(dt)
    if not self.connected then
        return
    end
    local event = self.host:service(50)
    while event do
        local data = event.data
        if event.type == "connect" then
            self.connected = true
            self.callbacks.connected(event.peer)
            if not self.__nameSend then
                local key = math.floor(os.clock() + os.time() + .5) + math.random(0, 99999999)
                self.key = key

                self:sendInfo({
                    name = self.name,
                    password = self.password,
                    key = self.key
                })
            
                self.__nameSend = true
            end

        elseif event.type == "receive" then
            print(data)
            data = decrypt(data, self.key)
            if data then
                data = module.json.decode(data)
            end

            if data and data.isEvent then
                self.callbacks.event(event.peer, data.events)
            elseif data then
                self.callbacks.message(event.peer, data.data)
            end


        elseif event.type == "disconnect" then
            self.connected = false
            self.callbacks.disconnected(event.peer, event.data)
        end

        event = self.host:service()
    end
end

function client:sendInfo(data)
    local pkg = module.new.package(data)
    local str = module.json.encode(pkg.info)
    self:sendRaw(str)
end

function client:sendRaw(data)
    if self.connected then
        if self.__nameSend then
            data = encrypt(data, self.key)
        end
        self.server:send(data)
    end
end

function client:disconnect()
    self.server:disconnect(module.CLIENT_DISCONNECT)
    self.host:flush()
    self.connected = false
end

return module
