vim.api.nvim_create_user_command("PackUpdate", function(props)
    local names = props.fargs
    if #names == 0 then
      vim.api.nvim_echo({ {"no plugin names given"} }, false, { err = true })
      return
    end
    vim.pack.update(props.fargs)
end, {
    nargs = "*",
    complete = "packadd",
})
vim.api.nvim_create_user_command("PackSync", function()
    require("lynn").sync()
end, {})
vim.api.nvim_create_user_command("PackClean", function()
    require("lynn").clean()
end, {})
