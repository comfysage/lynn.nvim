local utils = {}

local aliases = {
    ['github'] = "https://github.com"
}

---@param str string
---@return string
function utils.norm_url(str)
    local s, n = string.gsub(str, '%w+:', function(s)
        local m, repl = vim.iter(pairs(aliases)):find(function(v, _)
            return (v .. ':') == s
        end)
        if not m then
            return
        end
        return repl .. '/'
    end, 1)
    if n == 0 then
        return utils.norm_url('github:' .. s)
    end
    if string.sub(s, -4) ~= '.git' then
        s = s .. '.git'
    end

    return s
end

---@param str string
---@return string
function utils.norm_name(str)
    do
        local m = string.match(str, '^n?vim[-](.+)')
        if m then
            str = m
        end
    end
    do
        local m = string.match(str, '(.+)%.n?vim$')
        if not m then
            m = string.match(str, '(.+)[.-]lua$')
        end
        if m then
            str = m
        end
    end
    return str
end

---@param url string
---@return string
function utils.get_name(url)
    return utils.norm_name(string.match(url, '([^/]+)%.git$'))
end

function utils.get_inactive()
    return vim.iter(ipairs(vim.pack.get())):map(function(_, v)
        -- assumes that all plugins are added to vim.pack even if not currently loaded
        if not v.active then
            return v
        end
    end):totable()
end

return utils
