
local lust = require "lust"
local json = require "json"
local thread = require "thread"
local internet = require "internet"
local inspect = require "inspect"
local Test = {}
local describe, it, expect = lust.describe, lust.it, lust.expect
local dep = {}
dep.serialize = json
dep.transport = {}

function dep.transport.tcp()
    return {}
end

function dep.transport.connect(sock, address, port)
    sock.internal = internet.open(address, port)
    return true
end

function dep.transport.send(sock, data)
    return sock.internal:write(data)
end

function dep.transport.recv(sock)
    return sock.internal:read()
end

function dep.transport.close (sock)
    return sock.interal:close()
end

dep.thread = {}

function dep.thread.create (f)
    return function (...)
        return thread.create(f, ...)
    end
end

local Builder = dofile("rpc.lua")
local RPC = Builder.inject(Builder, dep)

describe("RPC Test", function ()
    local server = RPC.Server:new()
    local client = RPC.Client:new()
    local thread1 = nil
    lust.before(function ()
        -- server:bind("*", 10021)
        -- server:listen(1024)
        -- thread1 = thread.create(server.run, server)
        client:connect("localhost", 10021)
        expect(client.socket).to.be.truthy()
    end)

    -- describe("Server module", function ()
    --     it("registerMethod", function ()
    --         server:registerMethod("add", add)
    --         expect(server.methods["add"]).to.be.truthy()
    --     end)
    --     it("unregisterMethod", function ()
    --         server:unregisterMethod("add")
    --         expect(server.methods["add"]).to_not.be.truthy()
    --     end)
    -- end)
    describe("Client module", function ()
        it("call", function ()
            local err, result = client:call("add", 1, 1)
            expect(err).to.be.truthy()
            expect(result).to.be(2)
            err, result = client:call("minus", 1, 1)
            expect(err).to.be.truthy()
            expect(result).to.be(0)
        end)
        it("batch call", function ()
            local err, result = client:batch(RPC.newRequest("add", 1, {1, 2}), RPC.newRequest("minus", 2, {2, 3}))
            print(inspect(result))
        end)
    end)
    lust.after(function ()
        thread1:kill()
        server:close()
        client:close()
    end)
end)

