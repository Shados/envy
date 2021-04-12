local split_rtp
split_rtp = function(rtp)
  return vim.api.nvim_call_function('split', {
    rtp,
    '\\\\\\@<!,'
  })
end
local rtp_string = vim.api.nvim_get_option('runtimepath')
local rtp_list = split_rtp(rtp_string)
local first_rtp, middle_rtp, last_rtp = "", "", ""
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
vim.api.nvim_set_var('envy_rtp_first', first_rtp)
vim.api.nvim_set_var('envy_rtp_middle', middle_rtp)
return vim.api.nvim_set_var('envy_rtp_last', last_rtp)
