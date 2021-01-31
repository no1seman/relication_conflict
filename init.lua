#!/usr/bin/env tarantool

require('strict').on()

if package.setsearchroot ~= nil then
    package.setsearchroot()
else
    -- Workaround for rocks loading in tarantool 1.10
    -- It can be removed in tarantool > 2.2
    -- By default, when you do require('mymodule'), tarantool looks into
    -- the current working directory and whatever is specified in
    -- package.path and package.cpath. If you run your app while in the
    -- root directory of that app, everything goes fine, but if you try to
    -- start your app with "tarantool myapp/init.lua", it will fail to load
    -- its modules, and modules from myapp/.rocks.
    local fio = require('fio')
    local app_dir = fio.abspath(fio.dirname(arg[0]))
    print('App dir set to ' .. app_dir)
    package.path = app_dir .. '/?.lua;' .. package.path
    package.path = app_dir .. '/?/init.lua;' .. package.path
    package.path = app_dir .. '/.rocks/share/tarantool/?.lua;' .. package.path
    package.path = app_dir .. '/.rocks/share/tarantool/?/init.lua;' ..
                       package.path
    package.cpath = app_dir .. '/?.so;' .. package.cpath
    package.cpath = app_dir .. '/?.dylib;' .. package.cpath
    package.cpath = app_dir .. '/.rocks/lib/tarantool/?.so;' .. package.cpath
    package.cpath = app_dir .. '/.rocks/lib/tarantool/?.dylib;' .. package.cpath
end

-- replication resolver

local my_space = 'profile'

local my_trigger =
    function(old, new, sp, op) -- op: ‘INSERT’, ‘DELETE’, ‘UPDATE’, or ‘REPLACE’
        if new == nil then
            print("No new during " .. op, old)
            return -- deletes are ok
        end
        if old == nil then
            print("Insert new, no old", new)
            return new -- insert without old value: ok
        end
        print(op .. " duplicate", old, new)
        if op == 'INSERT' then
            if new[2] > old[2] then
                -- Creating new tuple will change op to REPLACE
                return box.tuple.new(new)
                -- -- or, custom afterwork:
                -- box.on_commit(function()
                -- print("Do something after")
                -- box.space[sp]:replace(new)
                -- end)
            end
            return old
        end
        if new[2] > old[2] then
            return new
        else
            return old
        end
        return
    end

box.ctl.on_schema_init(function()
    box.space._space:on_replace(function(_, sp)
        if sp.name == my_space then
            box.on_commit(function()
                box.space[my_space]:before_replace(my_trigger)
            end)
        end
    end)
end)

-- configure cartridge

local cartridge = require('cartridge')

local ok, err = cartridge.cfg({
    roles = {
        'cartridge.roles.vshard-storage', 'cartridge.roles.vshard-router',
        'cartridge.roles.metrics', 'app.roles.api', 'app.roles.storage'
    },
    cluster_cookie = 'newapp-cluster-cookie'
})

assert(ok, tostring(err))

-- register admin function probe to use it with "cartridge admin"

local cli_admin = require('cartridge-cli-extensions.admin')

cli_admin.init()

local probe = {
    usage = 'Probe instance',
    args = {uri = {type = 'string', usage = 'Instance URI'}},
    call = function(opts)
        opts = opts or {}

        if opts.uri == nil then
            return nil, "Please, pass instance URI via --uri flag"
        end

        local cartridge_admin = require('cartridge.admin')
        local ok, err = cartridge_admin.probe_server(opts.uri)

        if not ok then return nil, err.err end

        return {string.format('Probe %q: OK', opts.uri)}
    end
}

local ok, err = cli_admin.register('probe', probe.usage, probe.args, probe.call)
assert(ok, err)
