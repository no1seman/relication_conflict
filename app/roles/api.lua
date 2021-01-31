local cartridge = require('cartridge')
local errors = require('errors')
local log = require('log')

local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")

local function json_response(req, json, status)
    local resp = req:render({json = json})
    resp.status = status
    return resp
end

local function internal_error_response(req, error)
    local resp = json_response(req, {
        info = "Internal error",
        error = error
    }, 500)
    return resp
end

local function profile_not_found_response(req)
    local resp = json_response(req, {
        info = "Profile not found"
    }, 404)
    return resp
end

local function profile_conflict_response(req)
    local resp = json_response(req, {
        info = "Profile already exist"
    }, 409)
    return resp
end

local function profile_unauthorized(req)
    local resp = json_response(req, {
        info = "Unauthorized"
    }, 401)
    return resp
end

local function storage_error_response(req, error)
    if error.err == "Profile already exist" then
        return profile_conflict_response(req)
    elseif error.err == "Profile not found" then
        return profile_not_found_response(req)
    elseif error.err == "Unauthorized" then
        return profile_unauthorized(req)
    else
        return internal_error_response(req, error)
    end
end

local function http_profile_add(req)
    local profile = req:json()
    local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id_mpcrc32(profile.profile_id)
    profile.bucket_id = bucket_id

    local resp, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'write',
        'profile_add',
        {profile}
    )

    if error then
        return internal_error_response(req, error)
    end
    if resp.error then
        return storage_error_response(req, resp.error)
    end

    return json_response(req, {info = "Successfully created"}, 201)
end

local function http_profile_update(req)
    local profile_id = tonumber(req:stash('profile_id'))
    local data = req:json()
    local changes = data.changes
    local password = data.password

    local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id_mpcrc32(profile_id)

    local resp, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'read',
        'profile_update',
        {profile_id, password, changes}
    )

    if error then
        return internal_error_response(req,error)
    end
    if resp.error then
        return storage_error_response(req, resp.error)
    end

    return json_response(req, resp.profile, 200)
end

local function http_profile_get(req)
    local profile_id = tonumber(req:stash('profile_id'))
    local password = req:json().password
    local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id_mpcrc32(profile_id)

    local resp, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'read',
        'profile_get',
        {profile_id, password}
    )

    if error then
        return internal_error_response(req, error)
    end
    if resp.error then
        return storage_error_response(req, resp.error)
    end

    return json_response(req, resp.profile, 200)
end

local function http_profile_delete(req)
    local profile_id = tonumber(req:stash('profile_id'))
    local password = req:json().password
    local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id_mpcrc32(profile_id)

    local resp, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'write',
        'profile_delete',
        {profile_id, password}
    )

    if error then
        return internal_error_response(req, error)
    end
    if resp.error then
        return storage_error_response(req, resp.error)
    end

    return json_response(req, {info = "Deleted"}, 200)
end

local function init(opts)
    if opts.is_master then
        box.schema.user.grant('guest',
            'read,write',
            'universe',
            nil, { if_not_exists = true }
        )
    end

    local httpd = cartridge.service_get('httpd')

    if not httpd then
        return nil, err_httpd:new("not found")
    end

    httpd:route(
        { path = '/auth/profile', method = 'POST', public = true },
        http_profile_add
    )
    httpd:route(
        { path = '/auth/profile/:profile_id', method = 'GET', public = true },
        http_profile_get
    )
    httpd:route(
        { path = '/auth/profile/:profile_id', method = 'PUT', public = true },
        http_profile_update
    )
    httpd:route(
        {path = '/auth/profile/:profile_id', method = 'DELETE', public = true},
        http_profile_delete
    )

    log.info("Added Auth API role")
    return true
end

return {
    role_name = 'app.roles.api',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-router'
    }
}
