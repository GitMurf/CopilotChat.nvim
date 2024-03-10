local M = {}

---@param sources table<table>|nil Additional sources to include with copilot_chat
function M.setup(sources)
  local has_cmp, cmp = pcall(require, 'cmp')
  if not has_cmp then
    vim.notify('nvim-cmp is not installed', vim.log.levels.ERROR)
    return
  end
  local function get_source_items()
    local items = require('CopilotChat').get_completion_items()
    ---@type { trigger_character: string, label: string, kind: string, detail: string, description: string }[]
    local cmp_items = {}
    for _, item in ipairs(items) do
      table.insert(cmp_items, {
        trigger_character = string.sub(item.word, 1, 1),
        -- label = string.sub(item.word, 2),
        label = item.word,
        -- kind = cmp.lsp.CompletionItemKind.Text,
        kind = item.kind,
        detail = item.info or item.word,
        description = item.menu,
      })
    end
    return cmp_items
  end
  local source_items = get_source_items()
  local source = {}
  source.new = function()
    return setmetatable({}, { __index = source })
  end

  source.get_trigger_characters = function()
    return { '@', '/' }
  end

  ---@diagnostic disable-next-line: unused-local
  source.complete = function(self, request, callback)
    -- vim.notify(vim.inspect(request), vim.log.levels.INFO)
    -- local cursor_info = request.context.cursor
    -- offset is 1-based and is position of start of word connected to current cursor position
    -- if cursor is on a word starting with a trigger character, it skips the trigger character
    local current_word_start = request.offset
    -- current line
    local current_line = request.context.cursor_line
    local check_trigger_char =
      string.sub(current_line, current_word_start - 1, current_word_start - 1)
    -- vim.notify('current_word_first_char: ' .. check_trigger_char, vim.log.levels.INFO)
    local trigger_characters = self.get_trigger_characters()
    if type(trigger_characters) == 'string' then
      trigger_characters = { trigger_characters }
    end
    -- check if trigger_characters contains the current word's first character
    local is_trigger_char_word = vim.tbl_contains(trigger_characters, check_trigger_char)
    if not is_trigger_char_word then
      callback({ isIncomplete = true })
      return
    end
    -- vim.notify(
    --   'this is a trigger word and should show: ' .. check_trigger_char,
    --   vim.log.levels.INFO
    -- )

    -- line str before cursor position (includes current character)
    local before_cursor = request.context.cursor_before_line

    -- line str after cursor position (does NOT include current character)
    -- local after_cursor = request.context.cursor_after_line

    -- current word where cursor is
    local input = string.sub(before_cursor, current_word_start - 1)
    -- vim.notify('real deal: "' .. input .. '"', vim.log.levels.INFO)
    -- everything before the current word including the trigger character
    local prefix = string.sub(request.context.cursor_before_line, 1, request.offset - 1)
    -- vim.notify('input: "' .. input .. '"', vim.log.levels.INFO)
    -- vim.notify('prefix: "' .. prefix .. '"', vim.log.levels.INFO)
    local trigger_char = check_trigger_char
    -- if vim.startswith(input, '@') and (prefix == '@' or vim.endswith(prefix, ' @')) then
    if
      vim.startswith(input, trigger_char)
      and (prefix == trigger_char or vim.endswith(prefix, ' ' .. trigger_char))
    then
      local items = {}
      for _, item in ipairs(source_items) do
        if item.trigger_character == trigger_char then
          table.insert(items, {
            label = item.label,
            -- kind = item.kind,
            kind = cmp.lsp.CompletionItemKind.Text,
            data = {
              trigger_character = item.trigger_character,
              label = item.label,
              kind = item.kind,
              detail = item.detail,
              description = item.description,
            },
            textEdit = {
              newText = item.label,
              range = {
                start = {
                  line = request.context.cursor.row - 1,
                  character = request.context.cursor.col - 1 - #input,
                },
                ['end'] = {
                  line = request.context.cursor.row - 1,
                  character = request.context.cursor.col - 1,
                },
              },
            },
          })
        end
      end
      callback({
        items = items,
        isIncomplete = false,
      })
    else
      callback({ isIncomplete = true })
    end
  end

  -- store chat buffer listed state to restore to this state after completion
  -- nvim-cmp for some reason changes buffer to listed when accepting a completion
  local buf_is_listed = nil

  ---@diagnostic disable-next-line: unused-local
  source.resolve = function(self, completion_item, callback)
    buf_is_listed = vim.api.nvim_get_option_value('buflisted', { buf = 0 })

    -- local trigger_character = completion_item.data.trigger_character or ''
    local label = completion_item.data.label or ''
    local kind = completion_item.data.kind or ''
    local detail = completion_item.data.detail or ''
    local description = completion_item.data.description or ''

    -- vim.notify('resolve completion_item: ' .. vim.inspect(completion_item), vim.log.levels.INFO)
    -- vim.notify(
    --   'individual props:'
    --     .. '\ntrigger_character: '
    --     .. trigger_character
    --     .. '\nlabel: '
    --     .. label
    --     .. '\nkind: '
    --     .. kind
    --     .. '\ndetail: '
    --     .. detail
    --     .. '\ndescription: '
    --     .. description,
    --   vim.log.levels.INFO
    -- )

    if detail ~= '' or description ~= '' then
      -- completion_item.detail = detail
      -- completion_item.documentation = {
      --   kind = kind,
      --   value = description,
      -- }
      local doc_title = ''
      local doc_body = ''
      if kind == 'context' then
        doc_title = 'Context: ' .. detail
        doc_body = description
      elseif kind == 'user' then
        doc_title = 'User Prompt: ' .. label
        doc_body = detail
      else
        doc_title = 'System Prompt: ' .. label
        doc_body = detail
      end

      local doc_string = doc_title .. '\n\n' .. doc_body
      -- vim.notify('setting documentation to: ' .. doc_string, vim.log.levels.INFO)
      completion_item.documentation = doc_string
    end

    -- if data.stat and data.stat.type == 'file' then
    --   local ok, documentation = pcall(function()
    --     return self:_get_documentation(data.path, constants.max_lines)
    --   end)
    --   if ok then
    --     completion_item.documentation = documentation
    --   end
    -- end
    -- vim.notify('resolved completion_item: ' .. vim.inspect(completion_item), vim.log.levels.INFO)
    callback(completion_item)
  end

  -- source.execute = function(self, completion_item, callback)
  --   -- vim.notify('execute completion_item: ' .. vim.inspect(completion_item), vim.log.levels.INFO)
  -- end

  ---Executed after the item was selected.
  ---@param completion_item lsp.CompletionItem
  ---@param callback fun(completion_item: lsp.CompletionItem|nil)
  function source:execute(completion_item, callback)
    callback(completion_item)
    local check_buf_listed = vim.api.nvim_get_option_value('buflisted', { buf = 0 })
    if check_buf_listed ~= buf_is_listed then
      -- reset the buffer listed status to what it was before completion
      vim.api.nvim_set_option_value('buflisted', buf_is_listed, { buf = 0 })
    end
  end

  cmp.register_source('copilotchat', source.new())

  sources = sources or { { name = 'buffer' } }
  table.insert(sources, { name = 'copilotchat' })

  cmp.setup.filetype('copilotchat', {
    sources = cmp.config.sources(sources),
    window = {
      documentation = {
        zindex = 1001,
      },
    },
  })

  -- create autocmd for markdown filetype and check if file buffer name is "copilot-chat"
  -- vim.api.nvim_create_autocmd('FileType', {
  --   pattern = { 'markdown', 'md' },
  --   callback = function(ev)
  --     local buf_num = ev.buf
  --     local buf_name = vim.api.nvim_buf_get_name(buf_num)
  --     local buf_basename = vim.fn.fnamemodify(buf_name, ':t')
  --     if buf_basename == 'copilot-chat' then
  --       cmp.setup.buffer({
  --         sources = cmp.config.sources(sources),
  --         window = {
  --           documentation = {
  --             zindex = 1001,
  --           },
  --         },
  --       })
  --     end
  --   end,
  -- })
end

return M
