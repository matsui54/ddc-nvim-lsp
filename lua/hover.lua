local vim = vim
local api = vim.api
local feature = 'textDocument/hover'
local default_response_handler = vim.lsp.handlers[feature]

local hover_initialise = {
  buffer_changes = 0,
  complete_item = nil,
  complete_item_index = -1,
  insert_mode = false,
  window = nil
}

local hover = hover_initialise
local util = require 'util'

local complete_visible = function()
  return vim.fn.pumvisible() ~= 0
end

local get_markdown_lines = function(result)
  local markdown_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)

  return  vim.lsp.util.trim_empty_lines(markdown_lines)
end

local get_window_alignment = function(complete_columns, screen_columns)
  if complete_columns < screen_columns / 2 then
    alignment = 'right'
  else
    alignment = 'left'
  end

  return alignment
end

local create_window = function(method, result)
  return util.focusable_float(method, function()
    local markdown_lines = get_markdown_lines(result)
    if vim.tbl_isempty(markdown_lines) then return end

    local complete_display_info = vim.fn.pum_getpos()
    local alignment = get_window_alignment(complete_display_info['col'], api.nvim_get_option('columns'))

    local hover_buffer, hover_window

    hover_buffer, hover_window = util.fancy_floating_markdown(markdown_lines, {
      pad_left = 1; pad_right = 1;
      col = complete_display_info['col']; width = complete_display_info['width']; row = vim.fn.winline();
      align = alignment;
    })

    hover.window = hover_window

    if hover_window ~= nil and api.nvim_win_is_valid(hover_window) then
      vim.lsp.util.close_preview_autocmd({"CursorMoved", "BufHidden", "InsertCharPre"}, hover_window)
    end

    return hover_buffer, hover_window
  end)
end

local decode_user_data = function(user_data)
  if user_data == nil or (user_data ~= nil and #user_data == 0) then return end

  return  vim.fn.json_decode(user_data)
end

-- local client_with_hover = function()
--   for _, value in pairs(vim.lsp.buf_get_clients(0)) do
--     if value.resolved_capabilities.hover == false then return false end
--   end
-- 
--   return true
-- end

local buffer_changed = function()
  buffer_changes = api.nvim_buf_get_changedtick(0)
  if hover.buffer_changes == buffer_changes then return false end

  hover.buffer_changes = buffer_changes

  return hover.buffer_changes
end

local close_window = function()
  if hover.window == nil or not api.nvim_win_is_valid(hover.window) then return end

  api.nvim_win_close(hover.window, true)
end

local get_complete_item = function()
  local complete_info = api.nvim_call_function('complete_info', {{ 'eval', 'selected', 'items', 'user_data' }})
  if complete_info['selected'] == -1 or complete_info['selected'] == hover.complete_item_index then return false end

  hover.complete_item_index = complete_info['selected']

  return complete_info['items'][hover.complete_item_index + 1]
end

local open_preview = function(documentation)
  local syntax = documentation['kind'] or ''
  local contents = vim.lsp.util.convert_input_to_markdown_lines(documentation)
  if contents and #contents ~= 0 then
    print(vim.inspect(contents))
    print(#contents)
    local complete_display_info = vim.fn.pum_getpos()
    -- local alignment = get_window_alignment(complete_display_info['col'], api.nvim_get_option('columns'))
    vim.lsp.util.open_floating_preview(contents, syntax, {
      pad_left = 1; pad_right = 1;
      offset_x = complete_display_info['width'];
    })
  end
end

local show_complete_document = function()
  local complete_item = get_complete_item()
  local client = vim.lsp.buf_get_clients()
  if not complete_visible() or not buffer_changed() or not complete_item 
    or not client then return end

  local decoded_user_data = decode_user_data(complete_item['user_data'])
  if decoded_user_data == nil then return end
  vim.g.foo = decoded_user_data
  local decoded_item = decoded_user_data['lspitem']
  if decoded_item['documentation'] then
    open_preview(decoded_item['documentation'])
  else
    client[1]['request']('completionItem/resolve', decoded_item, function(_, _, res)
      -- print(vim.inspect(res))
      if res['documentation'] then
        open_preview(res['documentation'])
      end
    end)
  end
end

local show_help = function()
end

function M.open_floating_preview(contents, syntax, opts)
  validate {
    contents = { contents, 't' };
    syntax = { syntax, 's', true };
    opts = { opts, 't', true };
  }
  opts = opts or {}
  opts.wrap = opts.wrap ~= false -- wrapping by default
  opts.stylize_markdown = opts.stylize_markdown ~= false
  opts.close_events = opts.close_events or {"CursorMoved", "CursorMovedI", "BufHidden", "InsertCharPre"}

  local bufnr = api.nvim_get_current_buf()

  -- check if this popup is focusable and we need to focus
  if opts.focus_id and opts.focusable ~= false then
    -- Go back to previous window if we are in a focusable one
    local current_winnr = api.nvim_get_current_win()
    if npcall(api.nvim_win_get_var, current_winnr, opts.focus_id) then
      api.nvim_command("wincmd p")
      return bufnr, current_winnr
    end
    do
      local win = find_window_by_var(opts.focus_id, bufnr)
      if win and api.nvim_win_is_valid(win) and vim.fn.pumvisible() == 0 then
        -- focus and return the existing buf, win
        api.nvim_set_current_win(win)
        api.nvim_command("stopinsert")
        return api.nvim_win_get_buf(win), win
      end
    end
  end

  -- check if another floating preview already exists for this buffer
  -- and close it if needed
  local existing_float = npcall(api.nvim_buf_get_var, bufnr, "lsp_floating_preview")
  if existing_float and api.nvim_win_is_valid(existing_float) then
    api.nvim_win_close(existing_float, true)
  end

  local floating_bufnr = api.nvim_create_buf(false, true)
  local do_stylize = syntax == "markdown" and opts.stylize_markdown


  -- Clean up input: trim empty lines from the end, pad
  contents = M._trim(contents, opts)

  if do_stylize then
    -- applies the syntax and sets the lines to the buffer
    contents = M.stylize_markdown(floating_bufnr, contents, opts)
  else
    if syntax then
      api.nvim_buf_set_option(floating_bufnr, 'syntax', syntax)
    end
    api.nvim_buf_set_lines(floating_bufnr, 0, -1, true, contents)
  end

  -- Compute size of float needed to show (wrapped) lines
  if opts.wrap then
    opts.wrap_at = opts.wrap_at or api.nvim_win_get_width(0)
  else
    opts.wrap_at = nil
  end
  local width, height = M._make_floating_popup_size(contents, opts)

  local float_option = M.make_floating_popup_options(width, height, opts)
  local floating_winnr = api.nvim_open_win(floating_bufnr, false, float_option)
  if do_stylize then
    api.nvim_win_set_option(floating_winnr, 'conceallevel', 2)
    api.nvim_win_set_option(floating_winnr, 'concealcursor', 'n')
  end
  -- disable folding
  api.nvim_win_set_option(floating_winnr, 'foldenable', false)
  -- soft wrapping
  api.nvim_win_set_option(floating_winnr, 'wrap', opts.wrap)

  api.nvim_buf_set_option(floating_bufnr, 'modifiable', false)
  api.nvim_buf_set_option(floating_bufnr, 'bufhidden', 'wipe')
  M.close_preview_autocmd(opts.close_events, floating_winnr)

  -- save focus_id
  if opts.focus_id then
    api.nvim_win_set_var(floating_winnr, opts.focus_id, bufnr)
  end
  api.nvim_buf_set_var(bufnr, "lsp_floating_preview", floating_winnr)

  return floating_bufnr, floating_winnr
end

return {
  show_complete_document = show_complete_document,
  show_help = show_help
}
