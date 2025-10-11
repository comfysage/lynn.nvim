---@module 'lynn'

local lzrq = function(modname)
  return setmetatable({
    modname = modname,
  }, {
    __index = function(t, k)
      local m = rawget(t, "modname")
      return m and require(m)[k] or nil
    end,
  })
end

local utils = lzrq("lynn.utils")

local lynn = {}

-- utils --

local function logdebug(...)
  if vim.o.debug ~= "" then
    vim.notify(table.concat({ ... }, "\n"), vim.log.levels.DEBUG)
  end
end

local function logerr(...)
  vim.notify(table.concat({ ... }, "\n"), vim.log.levels.ERROR)

  if vim.o.debug == "throw" then
    error(table.concat({ ... }, "\n"))
  end
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
---@field build? string|function
---@field deps? lynn.plug.spec[]

---@class lynn.plug.spec : lynn.plug
---@field [1] string
---@field name? string
---@field url? string
---@field path? string

--- { [path]: { plug: <plug>, id: <id> } }
---@type table<string, { plug: lynn.plug, id: number }>
lynn.loaded = {}

lynn.packdir = vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt")

lynn.group = vim.api.nvim_create_augroup("lynn:lazy", { clear = true })

local n_loaded = 0

--- { [name]: <plug> }
---@class table<string, lynn.plug>
lynn.plugins = {}

-- hooks --

---@alias lynn.hook fun(spec: lynn.plug)
---@alias lynn.hook.builtin
---|'before'
---|'build'
---|'after'

---@type table<lynn.hook.builtin, lynn.hook>
lynn.default_hooks = {
  before = function(_) end,
  build = function(spec)
    if type(spec.build) ~= "string" then
      return
    end
    ---@type string
    ---@diagnostic disable-next-line: assign-type-mismatch
    local buildstr = spec.build
    if not buildstr or buildstr == "" then
      return
    end

    if string.sub(buildstr, 0, 1) == ":" then
      vim.cmd(string.sub(buildstr, 2))
      return
    end

    if string.sub(buildstr, 0, 1) == ">" then
      local shellstr = string.sub(buildstr, 2)

      vim.system(vim.split(shellstr, " "), {
        cwd = spec.path,
      }, function(result)
        if result.code == 0 then
          return
        end

        logerr("error running build command for " .. spec.name .. ":", "\t" .. result.stderr)
      end)
      return
    end
  end,
  after = function(spec)
    vim.cmd.runtime({ "config/" .. spec.name .. ".lua", bang = true })
  end,
}

---@param plug lynn.plug
---@param hook string
---@param fn function
local function wraphook(plug, hook, fn)
  if not fn or type(fn) ~= "function" then
    return
  end

  logdebug('running "' .. hook .. '" for plugin "' .. plug.name .. '"')
  do
    local ok, result = pcall(fn, plug)
    if not ok then
      logerr("error running " .. hook .. " function for " .. plug.name .. ":", "\t" .. result)
      return
    end
  end
end

---@param plug lynn.plug
---@param hook string
---@param use_default? boolean
function lynn.runhook(plug, hook, use_default)
  if type(hook) ~= "string" then
    return
  end
  local fn = plug[hook]
  if not fn or type(fn) ~= "function" then
    if not use_default then
      return
    end
    wraphook(plug, hook, lynn.default_hooks[hook])
    return
  end

  wraphook(plug, hook, fn)
end

---@param plug lynn.plug
---@return integer id
local function pack_lazy(plug)
  if type(plug.event) == "string" then
    ---@diagnostic disable-next-line: param-type-mismatch
    local event = vim.split(plug.event, " ")
    return vim.api.nvim_create_autocmd(event[1], {
      group = lynn.group,
      pattern = event[2],
      once = true,
      callback = function()
        lynn.plugadd(plug, true)
      end,
    })
  end

  return vim.api.nvim_create_autocmd(plug.event, {
    group = lynn.group,
    once = true,
    callback = function()
      lynn.plugadd(plug, true)
    end,
  })
end

--- load a plugin
--- - add the plugin to the loaded list
--- - check deps
--- - run |:packadd|
--- - run before/after hooks
--- - check if `after/` dirs should be loaded
---@param plug lynn.plug
---@param load? boolean
function lynn.plugadd(plug, load)
  if type(plug) == "string" then
    plug = lynn.plugins[plug]
  end
  if lynn.loaded[plug.path] then
    return
  end

  -- add dependencies
  if plug.deps then
    vim.tbl_map(lynn.register, plug.deps)
  end

  -- add to loaded
  n_loaded = n_loaded + 1
  lynn.loaded[plug.path] = { plug = plug, id = n_loaded }

  lynn.runhook(plug, "before", true)

  vim.cmd.packadd({ plug.name, bang = not load })

  lynn.runhook(plug, "after", true)

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
function lynn.norm(plug)
  if type(plug) == "string" then
    plug = { plug }
  end
  plug.url = plug.url or plug[1]
  if plug.path and not plug.url then
    plug.url = "file://" .. vim.fs.normalize(plug.path)
  end
  plug.url = utils.norm_url(plug.url)
  plug.name = plug.name or utils.get_name(plug.url)
  plug.path = plug.path or vim.fs.joinpath(lynn.packdir, plug.name)
  ---@diagnostic disable-next-line: cast-type-mismatch
  ---@cast plug lynn.plug
  return plug
end

--- translate lynn.plug to vim.pack.Spec format
---@param plug lynn.plug
---@return vim.pack.Spec
function lynn.translate(plug)
  return {
    src = plug.url,
    name = plug.name,
    version = plug.version,
    data = {
      before = plug.before,
      after = plug.after,
      build = plug.build,
    },
  }
end

--- register a plugin
---@param plug lynn.plug.spec|string
---@param nopack? boolean avoid adding the plugin to `vim.pack` until later
function lynn.register(plug, nopack)
  local p = lynn.norm(plug)

  lynn.plugins[p.name] = vim.tbl_extend("keep", p, lynn.plugins[p.name] or {})
  if not nopack then
    vim.pack.add({ lynn.translate(p) }, { load = false })
  end
end

--- load a plugin by either running `lynn.plugadd` or wrapping the callback in
--- an autocmd
---@param plug lynn.plug
function lynn.load(plug)
  if not plug.lazy then
    return lynn.plugadd(plug)
  elseif plug.event then
    return pack_lazy(plug)
  end

  return logerr("plugin " .. plug.name .. " is lazy but has no event")
end

--- load all plugins
function lynn.loadall()
  vim.iter(pairs(lynn.plugins)):each(function(name, spec)
    local ok, result = pcall(lynn.load, spec)
    if not ok then
      logerr('error while loading plugin "' .. name .. '":', "\t" .. result)
    end
  end)
end

--- import a list of plugins from a module
---@param modname string
function lynn.import(modname)
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

  local packspecs = vim
    .iter(ipairs(plugs))
    :map(function(_, p)
      return lynn.norm(p)
    end)
    :map(function(p)
      local ok, result = pcall(lynn.register, p, true)
      if not ok then
        logerr('error while registering plugin "' .. p.name .. '":', "\t" .. result)
        return
      end
      return lynn.translate(p)
    end)
    :totable()
  vim.pack.add(packspecs, { load = false })
end

--- run |lynn.import()| and run packload for all plugins
---@param modname? string
function lynn.setup(modname)
  if modname then
    lynn.import(modname)
  end

  lynn.loadall()

  vim.api.nvim_exec_autocmds("User", {
    pattern = "PackDone",
  })
end

function lynn.sync()
  -- update
  vim.pack.update()
end

--- delete inactive plugins.
--- these include all plugin directories that are not in `vim.pack`.
function lynn.clean()
  local inactive = utils.get_inactive()

  if #inactive == 0 then
    return
  end

  local pluglist = vim
    .iter(inactive)
    :map(function(p)
      return " - " .. p.spec.name .. "\n\t" .. p.path
    end)
    :totable()
  local plugstr = table.concat(pluglist, "\n")

  vim.ui.input({
    prompt = "Delete inactive plugins? (y/N)\n" .. plugstr,
  }, function(input)
    if string.lower(input) == "y" then
      vim.tbl_map(function(p)
        vim.fs.rm(p.path, { recursive = true })
      end, inactive)
    end
  end)
end

return lynn
