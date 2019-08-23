#!/usr/bin/env moon
c = require 'cmark'
ffi = require 'ffi'
inspect = require 'inspect'
json = require 'rapidjson'
lcmark = require 'lcmark'

import add_children, bullet_list, code, code_block, custom_block, document,
  get_children, heading, item, paragraph, emph, text from require 'cmark.builder'

local *


main = (cli_args) ->
  unless cli_args and #cli_args == 2
    print "#{cli_args[0]}: Bad CLI arguments given"
    os.exit(1)
  options = json.load(cli_args[1])
  options = [opt for opt in *options when not opt.internal]
  out = cli_args[2]

  doc = document {}
  append_header doc
  for opt in *options
    append_nodes_for_option doc, opt


  -- Render to CommonMark and write to the output file
  out_file = io.open out, 'w'
  out_file\write c.render_commonmark doc, c.OPT_DEFAULT, 80
  -- print c.render_commonmark doc, c.OPT_DEFAULT, 80


append_header = (node) ->
  builder_path = ((debug.getinfo 2, "S").source\sub 2)\match "(.*[/\\])"
  header_lines = [line for line in io.lines "#{builder_path}/options-header.md"]
  header = table.concat header_lines, "\n"
  for child in *(cmarkstr_to_nodes header)
    c.node_append_child node, child


append_nodes_for_option = (node, option) ->
  return if option.readOnly
  opt_node = option_to_cmark option
  c.node_append_child node, opt_node


-- Options are like:
-- {
--   declarations: { "file_one.nix", "file_two.nix" }
--   default: json value or string representation
--   description: "string"
--   example: json value or string representation

--   internal: bool
--   loc: { "sourcePins", "<name>", "_module", "args" } -- a key path
--   name: "string"
--   readOnly: bool
--   type: "string"
--   visible: bool
-- }
-- loc should only be used for sorting purposes? 'name' provides a string version of it
-- Custom nodes
option_to_cmark = (option, header_level=3) ->
  header = heading {
    level: header_level
    code option.name
  }
  description = opt_desc option.description
  properties = opt_properties option

  nodes = {
    on_enter: '<div class="option">'
    on_exit: '</div>'
    header, description, properties
  }
  return custom_block nodes


opt_properties = (option) ->
  list = bullet_list {}
  c.node_append_child list, item { paragraph {
    (emph { "Type:" }), text " #{option.type}"
  }}
  if option.default
    c.node_append_child list, item { paragraph {
      (emph { "Default:" }), opt_default_to_markdown option
    }}
  -- TODO render as checkbox instead?
  if option.readOnly
    c.node_append_child list, item { paragraph {
      (emph { "This option is read-only" })
    }}
  if option.example
    c.node_append_child list, item {
      paragraph { (emph { "Example:" }) },
      opt_example_to_markdown option
    }
  nodes = {
    on_enter: '<div class="option_properties">'
    on_exit:  '</div>'
    list
  }
  return custom_block nodes


opt_desc = (cmark_str, ...) ->
  -- Treat the description as markdown, parse it to produce cmark node tree
  desc_nodes = cmarkstr_to_nodes cmark_str
  desc_nodes.on_enter = '<div class="option_description">'
  desc_nodes.on_exit = '</div>'
  return custom_block desc_nodes


opt_default_to_markdown = (option) ->
  opt_val_to_markdown option, 'default'
opt_example_to_markdown = (option) ->
  opt_val_to_markdown option, 'example', true
opt_val_to_markdown = (option, key, block=false) ->
  val = option[key]
  type_ = type val
  md_val = switch type_
    when 'string'
      -- TODO get machine readable 'type' repr and use that here for this
      -- conditional
      if (option.type\sub 1, 3) == "str"
        "\"#{val}\""
      else
        val
    when 'table'
      if val._type and val._type == 'literalExample'
        val.text
      else
        json_nix_attrs_to_string val
    when 'function'
      if val == json.null
        "null"
      else
        error "Unexpected function passed to opt_val_to_markdown"
    when 'boolean'
      tostring val
    else
      error "Unexpected value type '#{type}' '#{val}' passed to opt_val_to_markdown"

  unless block
    return (text " "), code md_val
  else
    return nix_block md_val


nix_block = (str) ->
  return code_block {
    info: 'nix'
    str
  }


json_nix_attrs_to_string = (attrs, indent=0) ->
  inspect attrs, {
    process: (item, path) ->
      item if path[#path] ~= inspect.METATABLE
  }


cmarkstr_to_nodes = (cmark_str) ->
  return get_children(c.parse_document cmark_str, #cmark_str, c.OPT_DEFAULT)

main(arg)
