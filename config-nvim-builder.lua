local inspect = require("inspect")
local json = require("rapidjson")
local lfs = require("lfs")
local paths_json = json.load(arg[1])
local out = arg[2]
local wrapped_lfs_call
wrapped_lfs_call = function(fn_name, call, ...)
  local ok, errmsg, errno = call(...)
  if not (ok) then
    print("│   └─! " .. tostring(fn_name) .. "(" .. tostring(inspect({
      ...
    })) .. ") failed with errno " .. tostring(errno) .. ", message: `" .. tostring(errmsg) .. "`")
    return os.exit(1)
  else
    return ok
  end
end
local wrapped_link
wrapped_link = function(...)
  return wrapped_lfs_call("link", lfs.link, ...)
end
local wrapped_mkdir
wrapped_mkdir = function(...)
  return wrapped_lfs_call("mkdir", lfs.mkdir, ...)
end
local wrapped_attributes
wrapped_attributes = function(...)
  return wrapped_lfs_call("attributes", lfs.attributes, ...)
end
local strip_base
strip_base = function(path)
  return path:sub(#out + 2, -1)
end
local created_subpaths = { }
local mkdirp
mkdirp = function(base, subpath)
  if (subpath:sub(-1, -1)) == "/" then
    subpath = subpath:sub(1, #subpath - 1)
  end
  if not (created_subpaths[subpath]) then
    print("├── Creating directory '" .. tostring(subpath) .. "'")
    local cur_path = base
    for dir in subpath:gmatch("[^/]+") do
      cur_path = cur_path .. ("/" .. dir)
      local cur_subpath = strip_base(cur_path)
      if not (created_subpaths[cur_subpath]) then
        wrapped_mkdir(cur_path)
        local _ = created_subpaths[cur_subpath]
      end
    end
    created_subpaths[subpath] = true
  end
end
local ln
ln = function(old, new, symlink)
  if symlink == nil then
    symlink = false
  end
  local symarg
  if symlink then
    symarg = "-s "
  else
    local _ = ""
  end
  print("├── Linking '" .. tostring(old) .. "' to '" .. tostring(strip_base(new)) .. "'")
  return wrapped_link(old, new, symlink)
end
local char_count
char_count = function(str, char)
  return select(2, str:gsub(char, "%0"))
end
local symlink_path
symlink_path = function(paths)
  local path_n = 1
  while path_n <= #paths do
    local path = paths[path_n]
    local source, target
    source, target = path.source, path.target
    local mode = wrapped_attributes(source, "mode")
    local separator_count = char_count(target, "/")
    if separator_count > 0 then
      local dir_path = ""
      local i = 0
      for element in target:gmatch("[^/]+") do
        dir_path = dir_path .. (element .. "/")
        i = i + 1
        if i >= separator_count then
          break
        end
      end
      mkdirp(out, dir_path)
    end
    local _exp_0 = mode
    if "file" == _exp_0 then
      ln(source, tostring(out) .. "/" .. tostring(target), true)
    elseif "directory" == _exp_0 then
      mkdirp(out, target)
      local dir_iter, iter_state = lfs.dir(source)
      for child, _ in dir_iter,iter_state,nil do
        local _continue_0 = false
        repeat
          if child == "." or child == ".." then
            _continue_0 = true
            break
          end
          paths[#paths + 1] = {
            source = tostring(source) .. "/" .. tostring(child),
            target = tostring(target) .. "/" .. tostring(child)
          }
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
    else
      print("Unexpected mode: " .. tostring(mode))
    end
    path_n = path_n + 1
  end
end
print("┌ Creating neovim runtimepath directory at " .. tostring(out) .. "...")
wrapped_mkdir(out)
symlink_path(paths_json)
return print("└ Done!")
