envy = { }
local split_rtp
split_rtp = function(rtp)
  return vim.api.nvim_call_function('split', {
    rtp,
    '\\\\\\@<!,'
  })
end
local rtp_string = vim.api.nvim_get_option('runtimepath')
local rtp_list = split_rtp(rtp_string)
local first_rtp
local middle_rtp, last_rtp = "", ""
if #rtp_list > 0 then
  if #rtp_list == 1 then
    first_rtp = table.remove(rtp_list)
  else
    last_rtp = table.remove(rtp_list)
    first_rtp = table.remove(rtp_list, 1)
    middle_rtp = table.concat(rtp_list, ",")
  end
else
  first_rtp = vim.api.nvim_call_function('stdpath', {
    'config'
  })
end
envy.first_rtp = first_rtp
envy.middle_rtp = middle_rtp
envy.last_rtp = last_rtp
envy.automatic_subtables = {
  __index = function(t, k)
    if not (rawget(t, k)) then
      rawset(t, k, { })
    end
    return rawget(t, k)
  end
}
envy.before_rtp = ""
envy.after_rtp = ""
envy.lazy_filetype_plugins = setmetatable({ }, envy.automatic_subtables)
envy.lazy_command_plugins = setmetatable({ }, envy.automatic_subtables)
envy.lazy_mapped_plugins = setmetatable({ }, envy.automatic_subtables)
envy.load_triggers = setmetatable({ }, envy.automatic_subtables)
envy.set_rtp = function()
  envy.final_rtp = tostring(envy.first_rtp) .. tostring(envy.before_rtp) .. "," .. tostring(envy.middle_rtp) .. tostring(envy.after_rtp) .. "," .. tostring(envy.last_rtp)
  return vim.api.nvim_set_option('runtimepath', envy.final_rtp)
end
envy.setup_lazy_loading = function()
  for ft, _plugins in pairs(envy.lazy_filetype_plugins) do
    vim.api.nvim_command("autocmd FileType " .. tostring(ft) .. " lua envy.load_on_filetype('" .. tostring(ft) .. "')")
  end
  for cmd, plugins in pairs(envy.lazy_command_plugins) do
    if (vim.api.nvim_call_function('exists', {
      envy.vim_string(":" .. tostring(cmd))
    })) ~= 2 then
      local lua_args = "[" .. tostring(envy.vim_string(cmd)) .. ", '<bang>', <line1>, <line2>, <q-args>]"
      local lua_cmd = "call luaeval('envy.cmd_proxy(_A[1], _A[2], _A[3], _A[4], _A[5])', " .. tostring(lua_args) .. ")"
      local full_cmd = "command! -nargs=* -range -bang -complete=file " .. tostring(cmd) .. " " .. tostring(lua_cmd)
      vim.api.nvim_command(full_cmd)
    end
    for _index_0 = 1, #plugins do
      local plugin = plugins[_index_0]
      table.insert(envy.load_triggers[plugin], {
        cmd = cmd
      })
    end
  end
  for map, plugins in pairs(envy.lazy_mapped_plugins) do
    if (#(envy.mapcheck(map)) == 0) and (#(envy.mapcheck(map, 'i')) == 0) then
      local _list_0 = envy.map_types
      for _index_0 = 1, #_list_0 do
        local _des_0 = _list_0[_index_0]
        local mode, map_prefix, key_prefix
        mode, map_prefix, key_prefix = _des_0[1], _des_0[2], _des_0[3]
        local lua_args = "[" .. tostring(envy.vim_string(map)) .. ", " .. tostring(envy.vim_string(plugins)) .. ", " .. tostring(envy.vim_bool((mode ~= 'i'))) .. ", " .. tostring(envy.vim_string(key_prefix)) .. "]"
        local lua_cmd = "call luaeval('envy.map_proxy(_A[1], _A[2], _A[3], _A[4])', " .. tostring(lua_args) .. ")"
        vim.api.nvim_set_keymap(mode, map, tostring(map_prefix) .. ":<C-U> " .. tostring(lua_cmd) .. "<CR>", {
          noremap = true,
          silent = true
        })
      end
    end
    for _index_0 = 1, #plugins do
      local plugin = plugins[_index_0]
      table.insert(envy.load_triggers[plugin], {
        map = map
      })
    end
  end
end
envy.load_on_filetype = function(ft)
  local plugins = envy.lazy_filetype_plugins[ft]
  local syntax_path = "syntax/" .. tostring(ft) .. ".vim"
  return envy.load_plugins(plugins, {
    "plugin",
    "after/plugin"
  }, syntax_path, "after/" .. tostring(syntax_path))
end
envy.load_plugins = function(plugins, subdirs, before_file, after_file)
  envy.remove_load_triggers(plugins)
  for _index_0 = 1, #plugins do
    local plugin = plugins[_index_0]
    envy.before_rtp = tostring(envy.before_rtp) .. "," .. tostring(plugin)
    if envy.dir_exists(tostring(plugin) .. "/after") then
      envy.after_rtp = "," .. tostring(plugin) .. "/after" .. tostring(envy.after_rtp)
    end
  end
  envy.set_rtp()
  for _index_0 = 1, #plugins do
    local plugin = plugins[_index_0]
    for _index_1 = 1, #subdirs do
      local dir = subdirs[_index_1]
      envy.source(plugin, {
        tostring(dir) .. "/**/*.vim"
      })
    end
    if before_file ~= nil then
      if envy.source(plugin, {
        before_file
      }) then
        if envy.globpath(plugin, after_file) then
          vim.api.nvim_command("runtime " .. tostring(before_file))
        end
      end
      envy.source(plugin, {
        after_file
      })
    end
  end
end
envy.remove_load_triggers = function(plugins)
  for _index_0 = 1, #plugins do
    local plugin = plugins[_index_0]
    local _list_0 = envy.load_triggers[plugin]
    for _index_1 = 1, #_list_0 do
      local trigger = _list_0[_index_1]
      if trigger.cmd then
        vim.api.nvim_command("silent! delc " .. tostring(trigger.cmd))
      end
      if trigger.map then
        vim.api.nvim_del_keymap("", trigger.map)
        vim.api.nvim_del_keymap("i", trigger.map)
      end
    end
    envy.load_triggers[plugin] = nil
  end
end
envy.dir_exists = function(dir)
  return (vim.api.nvim_call_function('isdirectory', {
    dir
  })) ~= 0
end
envy.source = function(plugin_dir, file_patterns)
  assert((type(file_patterns)) == "table")
  local any_exist = false
  for _index_0 = 1, #file_patterns do
    local pattern = file_patterns[_index_0]
    local _list_0 = (envy.globpath(plugin_dir, pattern))
    for _index_1 = 1, #_list_0 do
      local vim_file = _list_0[_index_1]
      vim.api.nvim_command("source " .. tostring(vim_file))
      any_exist = true
    end
  end
  return any_exist
end
envy.globpath = function(dir, pattern)
  return vim.api.nvim_call_function('globpath', {
    dir,
    pattern,
    false,
    true,
    false
  })
end
envy.vim_string = function(str)
  return vim.api.nvim_call_function('string', {
    str
  })
end
envy.cmd_proxy = function(cmd, bang, range_start, range_end, quoted_args)
  local plugins = envy.lazy_command_plugins[cmd]
  envy.lazy_load_plugins(plugins)
  local prefix
  if range_start == range_end then
    prefix = ""
  else
    prefix = tostring(range_start) .. "," .. tostring(range_end)
  end
  local real_cmd = string.format("%s%s%s %s", prefix, cmd, bang, quoted_args)
  return vim.api.nvim_command(real_cmd)
end
envy.lazy_load_plugins = function(plugins)
  envy.load_plugins(plugins, {
    'ftdetect',
    'after/ftdetect',
    'plugin',
    'after/plugin'
  })
  for _index_0 = 1, #plugins do
    local plugin_dir = plugins[_index_0]
    local _list_0 = {
      'ftdetect',
      'after/ftdetect',
      'ftplugin',
      'after/ftplugin'
    }
    for _index_1 = 1, #_list_0 do
      local subdir = _list_0[_index_1]
      if #(vim.api.nvim_call_function('finddir', {
        subdir,
        plugin_dir
      })) > 0 then
        if (vim.api.nvim_call_function('exists', {
          '#BufRead'
        })) ~= 0 then
          vim.api.nvim_command("doautocmd BufRead")
          break
        end
      end
    end
  end
end
envy.mapcheck = function(map, mode)
  local args = {
    map
  }
  if mode then
    table.insert(args, mode)
  end
  return vim.api.nvim_call_function('mapcheck', args)
end
envy.map_types = {
  {
    'i',
    '<C-O>',
    ''
  },
  {
    'n',
    '',
    ''
  },
  {
    'v',
    '',
    'gv'
  },
  {
    'o',
    '',
    ''
  }
}
envy.vim_bool = function(bool)
  if bool then
    return "v:true"
  else
    return "v:false"
  end
end
envy.map_proxy = function(map, plugins, maybe_with_prefix, key_prefix)
  envy.lazy_load_plugins(plugins)
  local extra_input = ""
  while true do
    local char = vim.api.nvim_call_function('getchar', {
      0
    })
    if char == 0 then
      break
    end
    extra_input = extra_input .. vim.api.nvim_call_function('nr2char', {
      char
    })
  end
  if maybe_with_prefix then
    local count = vim.api.nvim_get_vvar('count')
    local prefix
    if count > 0 then
      prefix = tostring(count)
    else
      prefix = ""
    end
    prefix = prefix .. "\"" .. tostring(vim.api.nvim_get_vvar('register')) .. tostring(key_prefix)
    if (vim.api.nvim_call_function('mode', {
      1
    })) == 'no' then
      local op = (vim.api.nvim_get_vvar('operator'))
      if op == 'c' then
        prefix = "\\<esc>" .. tostring(prefix)
      end
      prefix = prefix .. op
    end
    vim.api.nvim_feedkeys(prefix, 'n', false)
  end
  local replace = string.format("%c%c%c", 0x80, 253, 83)
  local escaped_map = string.gsub(map, "^<Plug>", replace, 1)
  local final_input = tostring(escaped_map) .. tostring(extra_input)
  return vim.api.nvim_feedkeys(final_input, '', true)
end
