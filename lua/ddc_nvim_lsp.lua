local api = vim.api

local request_candidates = function(params, callback)
  vim.lsp.buf_request(0, 'textDocument/completion', params, 
  function(_, _, result)
    local success = (type(result) == 'table' and not vim.tbl_isempty(result)
    ) and "1" or "0"
    result = result and result['items'] ~= nil and result['items'] or result

    if success ~= "0" then
      api.nvim_set_var('ddc#source#lsp#_results', result)
    end
    api.nvim_call_function('denops#request', {'ddc', callback, success})
  end)
end

return {
  request_candidates = request_candidates
}
