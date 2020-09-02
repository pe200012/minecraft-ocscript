
local lust = require "lust"
local cjson = require "cjson"
local lanes = require "lanes".configure()
local socket = require "socket"
local Test = {}
local describe, it, expect = lust.describe, lust.it, lust.expect
local dep = {}
dep.serialize = cjson
dep.transport = {}

function dep.transport.tcp()
    return socket.tcp()
end

function dep.transport.bind (sock, address, port)
    return sock:bind(address, port)
end

function dep.transport.listen (sock, backlog)
    return sock:listen(backlog)
end

function dep.transport.accept (sock)
    return sock:accept()
end

function dep.transport.connect(sock, address, port)
    return sock:connect(address, port)
end

function dep.transport.send(sock, data)
    return sock:send(data)
end

function dep.transport.recv(sock)
    return sock:receive()
end

function dep.transport.close (sock)
    return sock:close()
end

dep.thread = {}

function dep.thread.create (f)
    return lanes.gen("*", f)
end

local RPC = require "rpc":inject(dep)

describe("RPC Test", function ()
    local server = RPC.Server:new()
    local client = RPC.Client:new()
    local thread1 = nil
    local add = function (a, b)
        return a + b
    end
    lust.before(function ()
        server:bind("*", 10021)
        server:listen(1024)
        thread1 = lanes.gen("", server.run)(server)
        client:connect("localhost", 10021)
    end)

    describe("Server module", function ()
        it("registerMethod", function ()
            server:registerMethod("add", add)
            expect(server.methods["add"]).to.be.truthy()
        end)
        it("unregisterMethod", function ()
            server:unregisterMethod("add")
            expect(server.methods["add"]).to_not.be.truthy()
        end)
    end)
    lust.after(function ()
        thread1:cancel(0, true)
        server:close()
        client:close()
    end)
end)

