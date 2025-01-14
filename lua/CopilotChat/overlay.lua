---@class CopilotChat.Overlay
---@field name string
---@field bufnr number
---@field create fun(self: CopilotChat.Overlay)
---@field valid fun(self: CopilotChat.Overlay)
---@field validate fun(self: CopilotChat.Overlay)
---@field show fun(self: CopilotChat.Overlay, text: string, filetype: string?, winnr: number)
---@field restore fun(self: CopilotChat.Overlay, winnr: number, bufnr: number)
---@field delete fun(self: CopilotChat.Overlay)
---@field show_help fun(self: CopilotChat.Overlay, msg: string, offset: number)

local utils = require('CopilotChat.utils')
local class = utils.class

local Overlay = class(function(self, name, help, on_buf_create)
  self.name = name
  self.help = help
  self.help_ns = vim.api.nvim_create_namespace('copilot-chat-help')
  self.on_buf_create = on_buf_create
  self.bufnr = nil
end)

function Overlay:create()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = self.name
  vim.bo[bufnr].modifiable = false
  vim.api.nvim_buf_set_name(bufnr, self.name)
  return bufnr
end

function Overlay:valid()
  return utils.buf_valid(self.bufnr)
end

function Overlay:validate()
  if self:valid() then
    return
  end

  self.bufnr = self:create()
  self.on_buf_create(self.bufnr)
end

function Overlay:show(text, filetype, winnr, syntax)
  if not text or vim.trim(text) == '' then
    return
  end

  self:validate()
  text = text .. '\n'

  vim.api.nvim_win_set_buf(winnr, self.bufnr)
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, vim.split(text, '\n'))
  vim.bo[self.bufnr].modifiable = false
  self:show_help(self.help, -1)
  vim.api.nvim_win_set_cursor(winnr, { vim.api.nvim_buf_line_count(self.bufnr), 0 })

  filetype = filetype or 'text'
  syntax = syntax or filetype

  -- Dual mode with treesitter (for diffs for example)
  local ok, parser = pcall(vim.treesitter.get_parser, self.bufnr, syntax)
  if ok and parser then
    vim.treesitter.start(self.bufnr, syntax)
    vim.bo[self.bufnr].syntax = filetype
  else
    vim.bo[self.bufnr].syntax = syntax
  end
end

function Overlay:restore(winnr, bufnr)
  vim.api.nvim_win_set_buf(winnr, bufnr or 0)
end

function Overlay:delete()
  if self:valid() then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
end

function Overlay:show_help(msg, offset)
  if not msg then
    return
  end

  msg = vim.trim(msg)
  if msg == '' then
    return
  end

  self:validate()
  local line = vim.api.nvim_buf_line_count(self.bufnr) + offset
  vim.api.nvim_buf_set_extmark(self.bufnr, self.help_ns, math.max(0, line - 1), 0, {
    id = 1,
    hl_mode = 'combine',
    priority = 100,
    virt_lines = vim.tbl_map(function(t)
      return { { t, 'CopilotChatHelp' } }
    end, vim.split(msg, '\n')),
  })
end

return Overlay
