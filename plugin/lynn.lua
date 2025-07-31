vim.api.nvim_create_user_command("PackSync", function()
    require("lynn").sync()
end, {})
