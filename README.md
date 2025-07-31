lynn - native-first neovim plugin manager with charm

lynn is a small plugin manager built around neovim’s native `vim.pack` system.
it's designed to feel invisible - doing just enough to ease plugin use without layering on complexity.
ideal for native-first distros or anyone who prefers minimal configuration flow.

###### features

- manages plugins using `vim.pack`
- declarative plugin list stored in a single file
- integrates softly into the neovim lifecycle

###### why lynn?

- no bootstrapping code in your `init.lua`
- no abstraction over how plugins are actually loaded
- just a clear place to define what you want, and a helper to make it happen
- keeps your plugin specs simple

###### usage

1. define your plugins in `lua/plugins.lua` (or wherever you choose)
2. call `require("lynn").setup("plugins")` from your config
3. lynn handles passing your plugins to `vim.pack.add` and gives you a simple way to add lazy-loading

###### plugin spec

you can define your plugin spec like this:

```lua
{
  "owner/repo", -- or `url = "owner/repo"`/`url = "https://github.com/owner/repo"`
  name = "plugin-name", -- optionally rename the plugin
  event = "BufEnter", -- optional event
}
```

as you can see there's no `opts` or `config` field.
instead lynn simply uses the `:runtime` command to source [your configs](#config) in `config/`.

###### config

lynn automatically sources any files in `config/` that match the plugin name.

this means you can simply create a `mini.lua` file in your `config/` directory
and whenever `mini.nvim` is loaded lynn will source it for you.

this means you dont need to clutter your `lua/plugins/` directory with config
functions anymore - they're just separate files.

###### requirements

- neovim 0.12+ (for `vim.pack`)
- git

###### footnote

lynn does not track plugin versions using a lockfile or manage updates automatically.
this is by design - the plugin is based entirely on the `vim.pack` engine.

---

for a working example, see [sylvee](https://github.com/comfysage/sylvee).
lynn is extracted from that project and maintained as a soft dependency.
