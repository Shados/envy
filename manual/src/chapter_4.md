# 4. Advanced Usage
This chapter provides some notes on more complicated usages of Envy.

## Plugin Merging
The [`mergePlugins`](options.html#mergeplugins) option can be used to merge
plugin directories into symlink trees. This is useful because it reduces the
number of directories that have to be added to neovim's `runtimepath`, and as a
result it can significantly improve neovim startup times.

There are some restrictions:
- It may break some plugins outright.
- It will only merge plugins that are within the same 'bucket' in the plugin
  load order (so that dependent plugins are still loaded after their
  dependencies).
- It will likely cause issues in cases of colliding file names.

As such, it is not enabled by default. If you do enable it, you can disable
merging on a per-plugin basis using the
[`pluginRegistry.<pluginName>.mergeable`](options.html#fullpluginregistrynamemergeable)
option.

## Layering Configuration
TODO
