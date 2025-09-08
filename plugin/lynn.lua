if vim.g.loaded_lynn then
  return
end

vim.g.loaded_lynn = true

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

local lynn = lzrq("lynn")

vim.api.nvim_create_autocmd("PackChanged", {
  group = vim.api.nvim_create_augroup("lynn:packchanged:build", { clear = true }),
  callback = function(ev)
    local kind = ev.data.kind ---@type string

    if kind == "install" or kind == "update" then
      local spec = ev.data.spec ---@type lynn.plug
      lynn.runhook(spec, "build", true)
    end
  end,
})

vim.api.nvim_create_user_command("PackUpdate", function(props)
  local names = props.fargs
  if #names == 0 then
    vim.api.nvim_echo({ { "no plugin names given" } }, false, { err = true })
    return
  end
  vim.pack.update(props.fargs)
end, {
  nargs = "*",
  complete = "packadd",
})
vim.api.nvim_create_user_command("PackSync", function()
  lynn.sync()
end, {})
vim.api.nvim_create_user_command("PackClean", function()
  lynn.clean()
end, {})
