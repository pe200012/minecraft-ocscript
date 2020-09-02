
local inspect = require "inspect"

local RPC = {}

function RPC:inject(components)
    local moduleInstance = self
    moduleInstance.transport = components.transport
    moduleInstance.serialize = components.serialize
    moduleInstance.thread = components.thread
    moduleInstance.Server.parentModule = moduleInstance
    moduleInstance.Client.parentModule = moduleInstance
    return moduleInstance
end

function RPC.newRequest(method, id, params)
    local req = {
        jsonrpc = "2.0",
        method = method,
        params = params,
    }
    if id then
        req.id = id
    end
    return req
end

function RPC.newNotification(method, params)
    return {
        jsonrpc = "2.0",
        method = method,
        params = params
    }
end

RPC.Response = {}

function RPC.Response:isResult()
    if self.result then
        return true
    else
        return false
    end
end

function RPC.Response:isError()
    if self.error then
        return true
    else
        return false
    end
end

function RPC.Response.newResult(result, id)
    assert(id)
    return {
        jsonrpc = "2.0",
        result = result,
        id = id
    }
end

function RPC.Response.newError(code, message, id, data)
    local error = {
        jsonrpc = "2.0",
        error = {
            code = code,
            message = message,
        },
    }
    if data then
        error.error.data = data
    end
    error.error.data.id = id
    return error
end

RPC.Server = {}

function RPC.Server:new()
    local stub = self
    local err = nil
    stub.socket, err = self.parentModule.transport.tcp()
    if not stub.socket then
        error(err)
    end
    return stub
end

function RPC.Server:bind(address, port)
    assert(type(address) == "string")
    assert(type(port) == "number")
    local e, err = self.parentModule.transport.bind(self.socket, address, port)
    if not e then
        error(err)
    end
    return true
end

function RPC.Server:listen(backlog)
    assert(type(backlog) == "number")
    local e, err = self.parentModule.transport.listen(self.socket, backlog)
    if not e then
        error(err)
    end
    return true
end

function RPC.Server:run()
    while true do
        local client, err = self.parentModule.transport.accept(self.socket)
        if not client then
            error(err)
        else
            self.parentModule.thread.create(self.handle)(self, client)
        end
    end
    return true
end

function RPC.Server:registerMethod(funcName, func)
    assert(type(funcName) == "string")
    self.methods[funcName] = func
    return true
end

function RPC.Server:unresigerMethod(funcName)
    assert(type(funcName) == "string")
    self.methods[funcName] = nil
    return true
end

function RPC.Server:handle(client)
    local hasNamedParameter = function (args)
        for k,_ in pairs(args) do
            if type(k) == "string" then
                return true
            end
        end
        return false
    end
    local singleRequest = function (req)
        local r = nil
        local successful = true
        repeat
            if hasNamedParameter(req.params) then
                successful, r = pcall(self.methods[req.method], req.params)
            else
                successful, r = pcall(self.method[req.method], table.unpack(req.params))
            end
            if not successful then
                break
            end
            return self.parentModule.Response.newResult(r, req.id)
        until true
        local e = "Invalid params"
        local code = -32602
        io.stderr:write(e)
        return self.parentModule.Response.newError(code, e, req.id, req.data)
    end
    while true do
        local msg, err = self.parentModule.transport.recv(self.socket)
        if not msg and err == "closed" then
            break
        elseif not msg then
            print(err)
            break
        else
            local successful, req = pcall(self.parentModule.serialize.decode, msg)
            if not successful then
                local e = "Parse error"
                local code = -32700
                io.stderr:write(e)
                self.parentModule.transport.send(self.socket, self.parentModule.serialize.encode(self.parentModule.Response.newError(code, e, req.id, req.data)))
            elseif not req.method then
                local e = "Invalid Request"
                local code = -32600
                io.stderr:write(e)
                self.parentModule.transport.send(self.socket, self.parentModule.serialize.encode(self.parentModule.Response.newError(code, e, req.id, req.data)))
            elseif not self.methods[req.method] then
                local e = "Method not found"
                local code = -32601
                io.stderr:write(e)
                self.parentModule.transport.send(self.socket, self.parentModule.serialize.encode(self.parentModule.Response.newError(code, e, req.id, req.data)))
                break
            elseif type(req) == "table" then
                local batch = {}
                local results = {}
                for k, v in pairs(req) do
                    batch[k] = self.parentModule.thread.create(function ()
                        results[k] = singleRequest(v)
                    end)()
                end
                self.parentModule.thread.waitForAll(batch)
                self.parentModule.transport.send(self.socket, self.parentModule.serialize.encode(results))
            else
                if not req.id then
                    singleRequest(req)
                else
                    self.parentModule.transport.send(self.socket, self.parentModule.serialize.encode(self.parentModule.Response.newResult(singleRequest(req), req.id)))
                end
            end
        end
    end
    return true
end

function RPC.Server:close()
    self.parentModule.transport.close(self.socket)
    return true
end

RPC.Client = {}

function RPC.Client:new()
    local stub = self
    local err = nil
    stub.socket, err = self.parentModule.transport.tcp()
    if not stub.socket then
        error(err)
    end
    return stub
end

function RPC.Client:connect(address, port)
    assert(type(address) == "string")
    assert(type(port) == "number")
    local e, err = self.parentModule.transport.connect(self.socket, address, port)
    if not e then
        error(err)
    end
    return true
end

function RPC.Client:call(funcName, ...)
    assert(type(funcName) == "string")
    local req = self.parentModule.serialize.encode(self.parentModule.newRequest(funcName, 1, {...}))
    self.parentModule.transport.send(self.socket, req)
    local res = self.parentModule.serialize.decode(self.parentModule.transport.recv(self.socket))
    if res.code then
        return false, res
    elseif type(res.result) == "table" then
        return true, table.unpack(res.result)
    else
        return true, res.result
    end
end

function RPC.Client:notify(funcName, ...)
    assert(type(funcName) == "string")
    local req = self.parentModule.serialize.encode(self.parentModule.newRequest(funcName, {...}))
    self.parentModule.transport.send(self.socket, req)
end

function RPC.Client:batch(...)
    local bat = {}
    for k, v in pairs({...}) do
        if v.id then 
            bat[k] = self.parentModule.newRequest(v.method, v.id, v.params)
        else
            bat[k] = self.parentModule.newNotification(v.method, v.params)
        end
    end
    local req = self.parentModule.serialize.encode(bat)
    self.parentModule.transport.send(self.socket, req)
    local res = self.parentModule.serialize.decode(self.parentModule.transport.recv(self.socket))
end

function RPC.Client:close()
    self.parentModule.transport.close(self.socket)
    return true
end


RPC.newServer = RPC.Server.new
RPC.newClient = RPC.Client.new

return RPC
