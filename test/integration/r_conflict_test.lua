local t = require('luatest')
local g = t.group('replication_conflict')
local yaml = require('yaml')

local helper = require('test.helper.integration')
local cluster = helper.cluster

local profile = {
    profile_id = 1,
    first_name = 'Ivanoff',
    sur_name = 'Ivan',
    patronymic = 'Ivanovich',
    shadow = 'dsfadsfdsafdsafdsaffds',
    salt = 'dsfadsfdsfdsafdsds',
    msgs_count = 1,
    service_info = 'tarantool',
    password = '12345678'
}

g.test_replication_conflict = function()
    local api, storage_1, storage_2

    for _, server in pairs(cluster.servers) do
        if server.alias == 'api-1' then api = server end
        if server.alias == 'storage-1-1' then storage_1 = server end
        if server.alias == 'storage-1-2' then storage_2 = server end
    end

    -- calculate bucket_id
    profile.bucket_id = api.net_box:eval(
                            "return require('cartridge').service_get('vshard-router').get():bucket_id_mpcrc32(...)",
                            {profile.profile_id})

    -- disable replication
    local disable_r = "rep_cfg = box.cfg.replication box.cfg{ replication = {}} return rep_cfg"
    local replication_1 = storage_1.net_box:eval(disable_r)
    local replication_2 = storage_2.net_box:eval(disable_r)

    -- insert profile into storage_1_1
    storage_1.net_box:eval("box.cfg({read_only = false}) return _G.profile_add(...)", {profile})

    -- insert profile into storage_1_2
    storage_2.net_box:eval("box.cfg({read_only = false}) return _G.profile_add(...)", {profile})

    -- enable replication
    storage_1.net_box:eval("box.cfg{ replication = ...}", {replication_1})
    storage_2.net_box:eval("box.cfg{ replication = ...}", {replication_2})

    require('fiber').sleep(5)
    -- check replication status
    t.assert_equals(storage_1.net_box:eval('return box.info.replication[2].downstream.status'), 'follow')
    t.assert_equals(storage_2.net_box:eval('return box.info.replication[1].downstream.status'), 'follow')
end
