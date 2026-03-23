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

local did_ui_enter = false
local notif_queue = nil
local function notify(...)
  if did_ui_enter then
    return vim.notify(...)
  end

  notif_queue = notif_queue or {}
  notif_queue[#notif_queue + 1] = { ... }
end

lynn.do_notify = function()
  did_ui_enter = true

  if not notif_queue then
    return
  end

  vim.schedule(function()
    for _, v in ipairs(notif_queue) do
      notify(unpack(v))
    end
    notif_queue = nil
  end)
end

---@param v any
---@return string
local function inspect(v)
  if type(v) == "table" and not vim.islist(v) then
    return table.concat(
      vim
        .iter(pairs(v))
        :map(function(key, value)
          return string.format("%s=%q", inspect(key), inspect(value))
        end)
        :totable(),
      " "
    )
  end

  return type(v) ~= "string" and vim.inspect(v) or v
end

---@param ... any
---@return string
local function logfmt(...)
  local c = { ... }
  local t = vim
    .iter(ipairs(c))
    :map(function(_, item)
      return inspect(item)
    end)
    :totable()
  return table.concat(t, " ")
end

---@param ... any
local function logdebug(...)
  if vim.o.debug ~= "" then
    notify(logfmt(...), vim.log.levels.DEBUG)
  end
end

---@param ... any
---@return string?
local function logerr(...)
  local l = logfmt(...)

  notify(l, vim.log.levels.ERROR)

  if vim.o.debug == "throw" then
    return error(l)
  end
end

---@param msg string
---@param trace string
---@return string?
local function logtrace(msg, trace)
  return logerr(string.format("lynn: %s:\n\t%s", msg, trace))
end

---@class lynn.plug
---@field name string
---@field url string
---@field path string
---@field version? string|vim.VersionRange
---@field lazy? boolean
---@field event? string|string[]
---@field init? function function run before loading the plugin
---@field load? function function run to load the plugin
---@field config? function function run after loading the plugin
---@field build? string|function
---@field deps? string[]

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
---|'init'
---|'load'
---|'config'
---|'build'

---@type table<lynn.hook.builtin, lynn.hook>
lynn.default_hooks = {
  init = function(_) end,
  load = function(spec)
    local ok, result = pcall(vim.cmd.packadd, { spec.name, bang = vim.v.vim_did_init == 0 })
    if not ok then
      logerr("error running |:packadd|", { ["spec.name"] = spec.name })
      return logtrace("load", result)
    end

    if not vim.v.vim_did_init == 0 then
      local after_paths = vim.fn.glob(spec.path .. "/after/plugin/**/*.{vim,lua}", false, true)
      vim.tbl_map(function(path)
        pcall(vim.cmd.source, vim.fn.fnameescape(path))
      end, after_paths)
    end
  end,
  config = function(spec)
    vim.cmd.runtime({ "config/" .. spec.name .. ".lua", bang = true })
  end,
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

    local result = vim
      .system(vim.split(buildstr, " "), {
        cwd = spec.path,
      })
      :wait()
    if result.code == 0 then
      return
    end

    logerr("error running build command", { ["spec.name"] = spec.name })
    return logtrace("build", result.stderr)
  end,
}

---@param plug lynn.plug
---@param hook string
---@param fn function
local function wraphook(plug, hook, fn)
  if not fn or type(fn) ~= "function" then
    return
  end

  logdebug("running hook", { hook = hook, ["plug.name"] = plug.name })
  do
    local ok, result = pcall(fn, plug)
    if not ok then
      logerr("error running hook", { hook = hook, ["plug.name"] = plug.name })
      return logtrace("wraphook", result)
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
        lynn.plugadd(plug)
      end,
    })
  end

  return vim.api.nvim_create_autocmd(plug.event, {
    group = lynn.group,
    once = true,
    callback = function()
      lynn.plugadd(plug)
    end,
  })
end

--- load a plugin
--- - add the plugin to the loaded list
--- - check deps
--- - run |:packadd|
--- - run init/config hooks
--- - check if `after/` dirs should be loaded
---@param plug lynn.plug
function lynn.plugadd(plug)
  if type(plug) == "string" then
    plug = lynn.plugins[plug]
  end
  if lynn.loaded[plug.path] then
    return
  end

  -- add dependencies
  if plug.deps then
    vim.tbl_map(lynn.load, plug.deps)
  end

  -- add to loaded
  n_loaded = n_loaded + 1
  lynn.loaded[plug.path] = { plug = plug, id = n_loaded }

  lynn.runhook(plug, "init", true)
  lynn.runhook(plug, "load", true)
  lynn.runhook(plug, "config", true)
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
      init = plug.init,
      load = plug.load,
      config = plug.config,
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
---@param name string
function lynn.load(name)
  local plug = lynn.plugins[name]
  if not plug then
    return logerr("plugin not found", { name = name })
  end

  if lynn.loaded[plug.path] then
    return
  end

  if not plug.lazy and not plug.event then
    return lynn.plugadd(plug)
  elseif plug.event then
    return pack_lazy(plug)
  end
end

--- load all plugins
function lynn.loadall()
  vim.iter(pairs(lynn.plugins)):each(function(name, _)
    local ok, result = pcall(lynn.load, name)
    if not ok then
      logerr("error while loading plugin", { name = name })
      return logtrace("load", result)
    end
  end)
end

--- import a list of plugins from a module
---@param plugins lynn.plug.spec[]|string plugins|modname
---@param nopack? boolean avoid adding the plugin to `vim.pack` until later
function lynn.import(plugins, nopack)
  if type(plugins) == "string" then
    logdebug("importing plugins", { modname = plugins, nopack = not not nopack })

    local ok, result = pcall(require, plugins)
    if not ok then
      logerr("failed to import module", { modname = plugins })
      return logtrace("import", result)
    end
    return lynn.import(result, nopack)
  end

  local packspecs = vim
    .iter(ipairs(plugins))
    :map(function(_, p)
      return lynn.norm(p)
    end)
    :map(function(p)
      local ok, result = pcall(lynn.register, p, true)
      if not ok then
        logerr("error while registering plugin", { ["plug.name"] = p.name })
        return logtrace("register", result or "")
      end
      return lynn.translate(p)
    end)
    :totable()
  if not nopack then
    vim.pack.add(packspecs, { load = false })
  end
end

--- run |lynn.import()| and run packload for all plugins
---@param plugins? lynn.plug.spec[]|string plugins|modname
---@param nopack? boolean avoid adding the plugin to `vim.pack` until later
function lynn.setup(plugins, nopack)
  if plugins then
    lynn.import(plugins, nopack)
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
    prompt = "Delete inactive plugins? (y/N)\n" .. plugstr .. "\n",
  }, function(input)
    if string.lower(input) == "y" then
      vim.tbl_map(function(p)
        vim.fs.rm(p.path, { recursive = true })
      end, inactive)
    end
  end)
end

return lynn
