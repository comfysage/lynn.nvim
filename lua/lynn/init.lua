local utils = require("lynn.utils")

local pack = {}

local function logdebug(...)
    if vim.o.verbose > 0 then
        vim.api.nvim_echo({ ... }, false, { kind = 'verbose', verbose = true })
    end
end

local function logerr(...)
    vim.api.nvim_echo({ ... }, true, { err = true })
end

---@class lynn.plug
---@field name string
---@field url string
---@field path string
---@field version? string|vim.VersionRange
---@field lazy? boolean
---@field event? string|string[]
---@field before? function
---@field after? function
---@field deps? lynn.plug.spec[]

---@class lynn.plug.spec : lynn.plug
---@field [1] string
---@field name? string
---@field url? string
---@field path? string

--- { [path]: { plug: <plug>, id: <id> } }
---@type table<string, { plug: lynn.plug, id: number }>
pack.loaded = {}

pack.packdir = vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt")

pack.group = vim.api.nvim_create_augroup("lynn", { clear = true })

local n_loaded = 0

--- { [name]: <plug> }
---@class table<string, lynn.plug>
pack.plugins = {}

vim.api.nvim_create_autocmd("User", {
    pattern = "PackLoadAll",
    group = pack.group,
    once = true,
    callback = function()
        pack.loadall()
    end,
})

-- utils --

---@alias lynn.hook fun(name: string)

pack.default_hooks = {
    after = function(name)
        vim.cmd.runtime({ "config/" .. name .. ".lua", bang = true })
    end,
}

local function wraphook(plug, hook, fn)
    if not fn or type(fn) ~= "function" then
        return
    end

    logdebug({ 'running "' .. hook .. '" for plugin "' .. plug.name .. '"' })
    do
        local ok, result = pcall(fn, plug.name)
        if not ok then
            vim.notify(
                "error running " .. hook .. " function for " .. plug.name .. ":\n\t" .. result,
                vim.log.levels.ERROR
            )
            return
        end
    end
end

---@param plug lynn.plug
---@param hook string
local function runhook(plug, hook)
    if type(hook) ~= "string" then
        return
    end
    local fn = plug[hook]
    if not fn or type(fn) ~= "function" then
        return wraphook(plug, hook, pack.default_hooks[hook])
    end

    wraphook(plug, hook, fn)
end

local function pack_lazy(plug)
    vim.api.nvim_create_autocmd(plug.event, {
        group = pack.group,
        once = true,
        callback = function()
            pack.plugadd(plug, true)
        end,
    })
end

---@param plug lynn.plug
---@param load? boolean
function pack.plugadd(plug, load)
    if type(plug) == "string" then
        plug = pack.plugins[plug]
    end
    if pack.loaded[plug.path] then
        return
    end

    -- add dependencies
    if plug.deps then
        vim.tbl_map(pack.register, plug.deps)
    end

    -- add to loaded
    n_loaded = n_loaded + 1
    pack.loaded[plug.path] = { plug = plug, id = n_loaded }

    runhook(plug, "before")

    vim.cmd.packadd({ plug.name, bang = not load })

    runhook(plug, "after")

    local should_load_after_dir = vim.v.vim_did_enter == 1 and load and vim.o.loadplugins

    if should_load_after_dir then
        local after_paths = vim.fn.glob(plug.path .. "/after/plugin/**/*.{vim,lua}", false, true)
        vim.tbl_map(function(path)
            pcall(vim.cmd.source, vim.fn.fnameescape(path))
        end, after_paths)
    end
end

---@param plug lynn.plug.spec|string
---@return lynn.plug
function pack.norm(plug)
    if type(plug) == "string" then
        plug = { plug }
    end
    plug.url = plug.url or plug[1]
    plug.url = utils.norm_url(plug.url)
    plug.name = plug.name or utils.get_name(plug.url)
    plug.path = plug.path or vim.fs.joinpath(pack.packdir, plug.name)
    ---@diagnostic disable-next-line: cast-type-mismatch
    ---@cast plug lynn.plug
    return plug
end

--- translate lynn.plug to vim.pack.Spec format
---@param plug lynn.plug
---@return vim.pack.Spec
function pack.translate(plug)
    return {
        src = plug.url,
        name = plug.name,
        version = plug.version,
    }
end

---@param plug lynn.plug.spec|string
function pack.register(plug)
    local p = pack.norm(plug)

    pack.plugins[p.name] = vim.tbl_extend("keep", p, pack.plugins[p.name] or {})
end

---@param plug lynn.plug
function pack.load(plug)
    if not plug.lazy then
        pack.plugadd(plug)
    elseif plug.event then
        pack_lazy(plug)
    end
end

function pack.loadall()
    vim.tbl_map(pack.load, pack.plugins)
end

---@param modname string
function pack.import(modname)
    local plugs

    do
        local ok, result = pcall(require, modname)
        if ok then
            plugs = result
        end
    end
    if not plugs then
        return
    end

    local packspecs = vim.iter(ipairs(plugs))
        :map(function(_, p)
            return pack.norm(p)
        end)
        :map(function(p)
            local ok, result = pcall(pack.register, p)
            if not ok then
                logerr({ 'error while registering plugin "' .. p.name .. '":\n\t' }, { result })
                return
            end
            return pack.translate(p)
        end)
        :totable()
    vim.pack.add(packspecs, { load = false })
end

---@param modname? string
function pack.setup(modname)
    if modname then
        pack.import(modname)
    end

    vim.api.nvim_exec_autocmds("User", {
        pattern = "PackLoadAll",
    })
end

function pack.sync()
    -- update
    vim.pack.update()
end

function pack.clean()
    local inactive = utils.get_inactive()

    if #inactive == 0 then
      return
    end

    local pluglist = vim.iter(inactive):map(function(p)
        return " - " .. p.spec.name .. "\n\t" .. p.path
    end):totable()
    local plugstr = table.concat(pluglist, "\n")

    local choice = vim.fn.confirm("Delete inactive plugins?\n" .. plugstr, "&Yes/&No", 2)
    if choice == 2 then
      return
    end
    vim.pack.del(inactive)
end

return pack
