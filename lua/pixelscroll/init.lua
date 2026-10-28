--- pixelscroll.nvim: pixel-smooth scrolling of Neovim windows in terminals that support
--- smooth scroll regions (the experimental "Ghostty Smooth" fork,
--- tlpinney/ghostty, also through its herdr fork).
---
--- Each normal window declares its text area as a region with
--- `ESC _ smooth;id;top;bottom;left;right;pos;max ESC \`. The terminal
--- slides the region by the trackpad's sub-row pixels and sends one wheel
--- event per whole row, so 'mousescroll' is set to one line. The window's
--- last row is the overscan row: it holds the next line, hidden until the
--- text slides up into it. Declarations are sent at the end of each redraw
--- through nvim_ui_send(), so they reach the terminal in the same
--- (synchronized) flush as the scrolled text.
---
--- Support is detected with `ESC _ smooth;? ESC \`: a `smooth;ok` reply
--- within two seconds means supported.
--- SMOOTH_SCROLL=1 / =0 overrides detection (inside herdr the query does
--- not reach the terminal).
local M = {}

local ns = vim.api.nvim_create_namespace("pixelscroll")
local state = {
  enabled = false,
  -- Declaration text last sent, and the window ids it declared.
  sent = "",
  ids = {},
}

local function apc(body)
  return "\27_smooth;" .. body .. "\27\\"
end

--- Regions for the current tabpage's normal windows, keyed by window id.
local function regions()
  local out = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      local info = vim.fn.getwininfo(win)[1]
      -- At least one visible row plus the overscan row.
      if info and info.height >= 2 and info.width >= 1 then
        local top = info.winrow - 1 + (info.winbar or 0)
        local left = info.wincol - 1
        local buf = vim.api.nvim_win_get_buf(win)
        local last = vim.api.nvim_buf_line_count(buf)
        out[win] = {
          top = top,
          bottom = top + info.height - 1,
          left = left,
          right = left + info.width - 1,
          pos = info.topline - 1,
          max = math.max(last - 1, 0),
        }
      end
    end
  end
  return out
end

local function declare()
  if not state.enabled then
    return
  end
  local current = regions()
  local parts, ids = {}, {}
  for win, r in pairs(current) do
    ids[win] = true
    parts[#parts + 1] =
      apc(table.concat({ win, r.top, r.bottom, r.left, r.right, r.pos, r.max }, ";"))
  end
  for win in pairs(state.ids) do
    if not ids[win] then
      parts[#parts + 1] = apc("off;" .. win)
    end
  end
  table.sort(parts)
  local text = table.concat(parts)
  if text ~= state.sent then
    state.sent, state.ids = text, ids
    if text ~= "" then
      vim.api.nvim_ui_send(text)
    end
  end
end

local function enable()
  if state.provider then
    return
  end
  state.provider = true
  state.enabled = true
  -- The terminal sends one wheel event per row it has slid.
  vim.o.mousescroll = "ver:1,hor:6"
  -- LazyVim animates scrolling by lines (snacks.nvim); that fights pixel scrolling.
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.scroll and snacks.scroll.disable then
    pcall(snacks.scroll.disable)
  end
  vim.api.nvim_set_decoration_provider(ns, { on_end = declare })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      vim.api.nvim_ui_send(apc("off"))
    end,
  })
  vim.g.pixelscroll = true
  vim.cmd.redraw({ bang = true })
end

local function probe()
  -- Nvim sends its own device attributes query at startup, so a DA1 reply
  -- says nothing about ours; wait a little for `smooth;ok` instead.
  local id
  id = vim.api.nvim_create_autocmd("TermResponse", {
    callback = function(ev)
      local seq = ev.data and ev.data.sequence or ""
      if seq:find("\27_smooth;ok", 1, true) then
        enable()
        return true
      end
    end,
  })
  vim.defer_fn(function()
    pcall(vim.api.nvim_del_autocmd, id)
  end, 2000)
  vim.api.nvim_ui_send(apc("?"))
end

--- Turns smooth scrolling off (rows) or back on, e.g. to compare.
function M.set(on)
  if on and not state.provider then
    enable()
    return
  end
  if on then
    state.enabled = true
    vim.o.mousescroll = "ver:1,hor:6"
    state.sent = ""
  else
    state.enabled = false
    vim.o.mousescroll = "ver:3,hor:6"
    vim.api.nvim_ui_send(apc("off"))
    state.sent, state.ids = "", {}
  end
  vim.g.pixelscroll = on
  vim.cmd.redraw({ bang = true })
end

--- Statusline helper: "≈ smooth" when active.
function M.status()
  return state.enabled and "≈ smooth" or ""
end

function M.setup(_opts)
  vim.api.nvim_create_user_command("PixelScroll", function(opts)
    local arg = opts.args
    if arg == "on" then
      M.set(true)
    elseif arg == "off" then
      M.set(false)
    else
      M.set(not state.enabled)
    end
  end, { nargs = "?", complete = function() return { "on", "off", "toggle" } end })
  local function start()
    local flag = vim.env.SMOOTH_SCROLL
    if flag == "1" then
      enable()
    elseif flag ~= "0" then
      probe()
    end
  end
  if vim.v.vim_did_enter == 1 and #vim.api.nvim_list_uis() > 0 then
    start()
  else
    vim.api.nvim_create_autocmd("UIEnter", { once = true, callback = start })
  end
end

return M
