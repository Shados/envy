-- TODO nvim 0.4/0.5 cross-compatibility setup to make working with options,
-- variables, and vim function calls easier

-- Chop up runtimepath variable for later reconstitution with plugin entries inserted {{{
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
first_rtp, middle_rtp, last_rtp = "", "", ""
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

vim.api.nvim_set_var 'envy_rtp_first', first_rtp
vim.api.nvim_set_var 'envy_rtp_middle', middle_rtp
vim.api.nvim_set_var 'envy_rtp_last', last_rtp
-- }}}
