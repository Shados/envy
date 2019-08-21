-- TODO cache all ops instead of just mkdir, and use the cache to do collision
-- detection in a useful fashion that points back to the source?
inspect = require "inspect"
json = require "rapidjson"
lfs = require "lfs"

paths_json = json.load(arg[1])
out = arg[2]


wrapped_lfs_call = (fn_name, call, ...) ->
  ok, errmsg, errno = call ...
  unless ok
    print "│   └─! #{fn_name}(#{inspect {...}}) failed with errno #{errno}, message: `#{errmsg}`"
    os.exit(1)
  else
    return ok
wrapped_link = (...) -> wrapped_lfs_call "link", lfs.link, ...
wrapped_mkdir = (...) -> wrapped_lfs_call "mkdir", lfs.mkdir, ...
wrapped_attributes = (...) -> wrapped_lfs_call "attributes", lfs.attributes, ...

strip_base = (path) ->
  -- Remove /nix/store/..../ prefix (+2 to get past the final /)
  path\sub #out + 2, -1

created_subpaths = {}
mkdirp = (base, subpath) ->
  if (subpath\sub -1, -1) == "/"
    subpath = subpath\sub(1,#subpath - 1)
  unless created_subpaths[subpath]
    print "├── Creating directory '#{subpath}'"
    cur_path = base
    for dir in subpath\gmatch("[^/]+")
      cur_path ..= "/" .. dir
      cur_subpath = strip_base cur_path
      unless created_subpaths[cur_subpath]
        wrapped_mkdir cur_path
        created_subpaths[cur_subpath]
    -- Cache directory creation
    created_subpaths[subpath] = true

ln = (old, new, symlink=false) ->
  symarg = "-s " if symlink else ""
  print "├── Linking '#{old}' to '#{strip_base new}'"
  wrapped_link old, new, symlink

char_count = (str, char) ->
  select 2, str\gsub(char, "%0")

symlink_path = (paths) ->
  path_n = 1
  while path_n <= #paths
    path = paths[path_n]

    import source, target from path
    mode = wrapped_attributes source, "mode"

    separator_count = char_count target, "/"
    if separator_count > 0
      -- Is a nested path, create parent directory
      dir_path = ""
      i = 0
      for element in target\gmatch("[^/]+")
        dir_path ..= element .. "/"
        i += 1
        break if i >= separator_count
      mkdirp out, dir_path

    switch mode
      when "file"
        ln source, "#{out}/#{target}", true
      when "directory"
        mkdirp out, target
        dir_iter, iter_state = lfs.dir source
        -- Skip . and ..
        iter_state\next!
        iter_state\next!
        -- Add child paths to the ones we're working on
        for child, _ in dir_iter, iter_state, nil
          paths[#paths + 1] = {
            source: "#{source}/#{child}"
            target: "#{target}/#{child}"
          }
      else
        print "Unexpected mode: #{mode}"

    path_n += 1

print "┌ Creating neovim runtimepath directory at #{out}..."
wrapped_mkdir out
symlink_path(paths_json)
print "└ Done!"
