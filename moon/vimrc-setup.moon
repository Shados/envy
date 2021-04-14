-- TODO nvim 0.4/0.5 cross-compatibility setup to make working with options,
-- variables, and vim function calls easier
export envy = {}

-- Chop up runtimepath variable for later reconstitution with plugin entries inserted. {{{
split_rtp = (rtp) ->
  -- NOTE: I attempted to implement this in native Lua at first, using
  -- `vim.split`, but it is backed on Lua's `string.find`, which doesn't let
  -- you split on a pattern where you keep a non-captured part of the pattern
  -- (we want to split on '[^\],', but want the [^\] character to remain in the
  -- first part of the split rather than being removed as a delimiter).
  -- It's still possible to implement this with string.find, but it's a PITA
  -- and we have vim's split function at hand, so why not use it?
  vim.api.nvim_call_function 'split', {rtp, '\\\\\\@<!,'}

rtp_string = vim.api.nvim_get_option 'runtimepath'
rtp_list = split_rtp rtp_string

-- We want to track the first runtimepath entry in order to insert the plugin
-- entries after it, doing the reverse for the last runtimepath entry as it is
-- likely the corresponding 'after' directory to the first entry. The
-- motivation for this is that the default spellfile is written to the first
-- writable directory in the runtimepath, and our plugin directories are
-- typically not writable (as they're in the Nix store). Ensuring the first
-- directory is *likely* a writable one short-circuits the spellfile
-- implementation's search.
local first_rtp
middle_rtp, last_rtp = "", ""
if #rtp_list > 0
  if #rtp_list == 1
    first_rtp = table.remove rtp_list
  else
    last_rtp = table.remove rtp_list
    first_rtp = table.remove rtp_list, 1
    middle_rtp = table.concat rtp_list, ","
else
  -- The first rtp entry must be a writable path for the default spellfile
  -- location to be written to, and this is the default first rtp entry, so we
  -- set it if the rtp is empty.
  first_rtp = vim.api.nvim_call_function 'stdpath', {'config'}

envy.first_rtp = first_rtp
envy.middle_rtp = middle_rtp
envy.last_rtp = last_rtp
-- }}}

-- Set these variables up so the Nix-generated Lua can populate them, these are
-- critical global state which is then used by the rtp-management and
-- lazy-loading functionality.
envy.automatic_subtables =
  __index: (t, k) ->
    unless rawget(t, k)
      rawset(t, k, {})
    return rawget(t, k)
envy.before_rtp = ""
envy.after_rtp = ""
envy.lazy_filetype_plugins = setmetatable {}, envy.automatic_subtables
envy.lazy_command_plugins = setmetatable {}, envy.automatic_subtables
envy.lazy_mapped_plugins = setmetatable {}, envy.automatic_subtables
envy.load_triggers = setmetatable {}, envy.automatic_subtables

-- Composes the final rtp from the initial value + the per-plugin entries, then
-- sets the actual vim option
envy.set_rtp = ->
  envy.final_rtp = "#{envy.first_rtp}#{envy.before_rtp},#{envy.middle_rtp}#{envy.after_rtp},#{envy.last_rtp}"
  vim.api.nvim_set_option 'runtimepath', envy.final_rtp

-- Create hooks and proxies to implement the lazy-loading functionlity
envy.setup_lazy_loading = ->
  for ft, _plugins in pairs envy.lazy_filetype_plugins
    -- TODO reimplement in Lua once neovim#12378 is merged
    vim.api.nvim_command "autocmd FileType #{ft} lua envy.load_on_filetype('#{ft}')"

  for cmd, plugins in pairs envy.lazy_command_plugins
    if (vim.api.nvim_call_function 'exists', {envy.vim_string ":#{cmd}"}) != 2
      -- If the command isn't already present, define it to use a proxy
      -- implementation
      -- TODO reimplement in Lua once neovim#11613 is merged
      lua_args = "[#{envy.vim_string cmd}, '<bang>', <line1>, <line2>, <q-args>]"
      lua_cmd = "call luaeval('envy.cmd_proxy(_A[1], _A[2], _A[3], _A[4], _A[5])', #{lua_args})"
      full_cmd = "command! -nargs=* -range -bang -complete=file #{cmd} #{lua_cmd}"
      vim.api.nvim_command full_cmd
    for plugin in *plugins
      -- Register the load triggers that were just configured, so they can be
      -- cleanly removed later
      table.insert envy.load_triggers[plugin], {:cmd}

  for map, plugins in pairs envy.lazy_mapped_plugins
    if (#(envy.mapcheck map) == 0) and (#(envy.mapcheck map, 'i') == 0)
      -- If the mapping isn't already present, define it to use a proxy
      -- implementation
      for {mode, map_prefix, key_prefix} in *envy.map_types
        lua_args = "[#{envy.vim_string map}, #{envy.vim_string plugins}, #{envy.vim_bool (mode != 'i')}, #{envy.vim_string key_prefix}]"
        lua_cmd = "call luaeval('envy.map_proxy(_A[1], _A[2], _A[3], _A[4])', #{lua_args})"
        vim.api.nvim_set_keymap mode, map, "#{map_prefix}:<C-U> #{lua_cmd}<CR>", {
          noremap: true
          silent: true
        }
    for plugin in *plugins
      -- Register the load triggers that were just configured, so they can be
      -- cleanly removed later
      table.insert envy.load_triggers[plugin], {:map}

envy.load_on_filetype = (ft) ->
  plugins = envy.lazy_filetype_plugins[ft]
  syntax_path = "syntax/#{ft}.vim"
  envy.load_plugins plugins, {"plugin", "after/plugin"}, syntax_path, "after/#{syntax_path}"

envy.load_plugins = (plugins, subdirs, before_file, after_file) ->
  envy.remove_load_triggers plugins

  -- Re-set runtimepath with new plugins included
  for plugin in *plugins
    rtp_dir = envy.escape_plugin_rtp plugin
    envy.before_rtp = "#{envy.before_rtp},#{rtp_dir}"
    if envy.dir_exists "#{plugin}/after"
      envy.after_rtp = ",#{rtp_dir}/after#{envy.after_rtp}"
  envy.set_rtp!

  -- Directly source & :runtime appropriate files
  for plugin in *plugins
    for dir in *subdirs
      envy.source plugin, {"#{dir}/**/*.vim"}
    if before_file != nil
      if envy.source plugin, {before_file}
        if envy.globpath plugin, after_file
          vim.api.nvim_command "runtime #{before_file}"
      envy.source plugin, {after_file}
    -- TODO throw a custom 'lazy plugin loaded' autocmd event here?

envy.remove_load_triggers = (plugins) ->
  for plugin in *plugins
    for trigger in *envy.load_triggers[plugin]
      if trigger.cmd
        vim.api.nvim_command "silent! delc #{trigger.cmd}"
      if trigger.map
        vim.api.nvim_del_keymap "", trigger.map
        vim.api.nvim_del_keymap "i", trigger.map
    envy.load_triggers[plugin] = nil

envy.escape_plugin_rtp = (plugin_rtp_path) ->
  string.gsub plugin_rtp_path, "([,\\])", "\\%1"

envy.dir_exists = (dir) ->
  (vim.api.nvim_call_function 'isdirectory', {dir}) != 0

envy.source = (plugin_dir, file_patterns) ->
  assert (type file_patterns) == "table"
  any_exist = false
  for pattern in *file_patterns
    for vim_file in *(envy.globpath plugin_dir, pattern)
      vim.api.nvim_command "source #{vim_file}"
      any_exist = true
  return any_exist

envy.globpath = (dir, pattern) ->
  vim.api.nvim_call_function 'globpath', {dir, pattern, false, true, false}

envy.vim_string = (str) ->
  vim.api.nvim_call_function 'string', {str}

envy.cmd_proxy = (cmd, bang, range_start, range_end, quoted_args) ->
  plugins = envy.lazy_command_plugins[cmd]
  envy.lazy_load_plugins plugins

  -- Run the actual, backing command
  prefix = if range_start == range_end
    ""
  else
    "#{range_start},#{range_end}"
  real_cmd = string.format "%s%s%s %s", prefix, cmd, bang, quoted_args
  vim.api.nvim_command real_cmd

envy.lazy_load_plugins = (plugins) ->
  -- Load the plugin(s)
  envy.load_plugins plugins, {'ftdetect', 'after/ftdetect', 'plugin', 'after/plugin'}

  -- Re-trigger a BufRead event if any ftdetect or ftplugin directories are
  -- present in the plugin(s)
  for plugin_dir in *plugins
    for subdir in *{'ftdetect', 'after/ftdetect', 'ftplugin', 'after/ftplugin'}
      if #(vim.api.nvim_call_function 'finddir', {subdir, plugin_dir}) > 0
        if (vim.api.nvim_call_function 'exists', {'#BufRead'}) != 0
          vim.api.nvim_command "doautocmd BufRead"
          break

envy.mapcheck = (map, mode) ->
  args = {map}
  if mode
    table.insert args, mode
  vim.api.nvim_call_function 'mapcheck', args

envy.map_types = {
  {'i', '<C-O>', ''},
  {'n', '', ''},
  {'v', '', 'gv'},
  {'o', '', ''},
}

envy.vim_bool = (bool) ->
  if bool
    "v:true"
  else
    "v:false"

envy.map_proxy = (map, plugins, maybe_with_prefix, key_prefix) ->
  envy.lazy_load_plugins plugins

  -- Capture any additional input following the mapping
  extra_input = ""
  while true
    char = vim.api.nvim_call_function 'getchar', {0}
    break if char == 0
    extra_input ..= vim.api.nvim_call_function 'nr2char', {char}

  -- Replay the real mapping + subsequent input now that the backing plugin is
  -- loaded
  if maybe_with_prefix
    count = vim.api.nvim_get_vvar 'count'
    prefix = if count > 0
      "#{count}"
    else
      ""
    prefix ..= "\"#{vim.api.nvim_get_vvar 'register'}#{key_prefix}"

    if (vim.api.nvim_call_function 'mode', {1}) == 'no'
      op = (vim.api.nvim_get_vvar 'operator')
      if op == 'c'
        prefix = "\\<esc>#{prefix}"
      prefix ..= op

    vim.api.nvim_feedkeys prefix, 'n', false
  -- NOTE: No way to replace with "\<Plug>" quote-expr we'd use in vimscript,
  -- so we just directly replace with the bytes that the quote-expr produces.
  -- This is admittedly kind-of cursed. See:
  -- https://github.com/neovim/neovim/blob/b535575acdb037c35a9b688bc2d8adc2f3dece8d/src/nvim/keymap.h#L117-L123
  -- (also L18-L26, L54-L58, L225)
  replace = string.format "%c%c%c", 0x80, 253, 83
  escaped_map = string.gsub map, "^<Plug>", replace, 1
  final_input = "#{escaped_map}#{extra_input}"
  vim.api.nvim_feedkeys final_input, '', true
