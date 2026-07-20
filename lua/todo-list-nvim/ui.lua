local todo = require("todo-list-nvim.todo")
local config = require("todo-list-nvim.config")
local highlights = require("todo-list-nvim.highlights")

local M = {}

---@class UiState
---@field buf integer|nil
---@field win integer|nil
---@field todos TodoItem[]
---@field width integer

---@type UiState
local state = {
	buf = nil,
	win = nil,
	todos = {},
	width = 72,
}

local NS = vim.api.nvim_create_namespace("todo-list-nvim")

local HEADER_LINES = 3
local DUE_COL_WIDTH = 15 -- "due YYYY-MM-DD"
local BADGE = "OVERDUE"
local BADGE_WIDTH = #BADGE + 2 -- "  OVERDUE"

local function is_open()
	return state.win
		and vim.api.nvim_win_is_valid(state.win)
		and state.buf
		and vim.api.nvim_buf_is_valid(state.buf)
end

local function close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
	state.todos = {}
end

---@param s string
---@param max_width integer
---@return string
local function truncate(s, max_width)
	if max_width < 1 then
		return ""
	end
	if vim.fn.strdisplaywidth(s) <= max_width then
		return s
	end
	if max_width <= 1 then
		return "…"
	end
	local budget = max_width - 1
	local lo, hi = 0, vim.fn.strchars(s)
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		local part = vim.fn.strcharpart(s, 0, mid)
		if vim.fn.strdisplaywidth(part) <= budget then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return vim.fn.strcharpart(s, 0, lo) .. "…"
end

---@param s string
---@param width integer
---@return string
local function pad_right(s, width)
	local w = vim.fn.strdisplaywidth(s)
	if w >= width then
		return s
	end
	return s .. string.rep(" ", width - w)
end

---@class LineSegments
---@field text string
---@field checkbox_col integer 0-based byte start
---@field checkbox_end integer
---@field title_col integer
---@field title_end integer
---@field due_col integer|nil
---@field due_end integer|nil
---@field badge_col integer|nil
---@field badge_end integer|nil
---@field overdue boolean
---@field completed boolean

---Build a column-aligned todo line and byte ranges for highlights.
---@param item TodoItem
---@param width integer
---@return LineSegments
local function format_line(item, width)
	local mark = item.completed and "[x]" or "[ ]"
	local overdue = todo.is_overdue(item)
	local due_text = item.due_at and ("due " .. item.due_at) or ""
	local badge_text = overdue and BADGE or ""

	local prefix = " " .. mark .. "  "
	local right_w = 0
	if due_text ~= "" then
		right_w = right_w + DUE_COL_WIDTH
	end
	if badge_text ~= "" then
		right_w = right_w + BADGE_WIDTH
	end

	local title_budget = math.max(8, width - vim.fn.strdisplaywidth(prefix) - right_w - 1)
	local title = truncate(item.title, title_budget)
	local title_padded = pad_right(title, title_budget)

	local parts = { prefix, title_padded }
	local checkbox_col = 1 -- after leading space
	local checkbox_end = checkbox_col + #mark
	local title_col = #prefix
	local title_end = title_col + #title

	local due_col, due_end, badge_col, badge_end

	if due_text ~= "" then
		local due_padded = pad_right(due_text, DUE_COL_WIDTH)
		due_col = #table.concat(parts)
		table.insert(parts, due_padded)
		due_end = due_col + #due_text
	end

	if badge_text ~= "" then
		table.insert(parts, "  ")
		badge_col = #table.concat(parts)
		table.insert(parts, badge_text)
		badge_end = badge_col + #badge_text
	end

	return {
		text = table.concat(parts),
		checkbox_col = checkbox_col,
		checkbox_end = checkbox_end,
		title_col = title_col,
		title_end = title_end,
		due_col = due_col,
		due_end = due_end,
		badge_col = badge_col,
		badge_end = badge_end,
		overdue = overdue,
		completed = item.completed,
	}
end

---@param row integer 0-based
---@param seg LineSegments
local function apply_row_highlights(row, seg)
	local hl = vim.api.nvim_buf_add_highlight
	hl(state.buf, NS, "TodoListNvimCheckbox", row, seg.checkbox_col, seg.checkbox_end)

	local title_hl = seg.completed and "TodoListNvimTitleDone" or "TodoListNvimTitle"
	hl(state.buf, NS, title_hl, row, seg.title_col, seg.title_end)

	if seg.due_col and seg.due_end then
		local due_hl = (seg.overdue and not seg.completed) and "TodoListNvimOverdue" or "TodoListNvimDue"
		hl(state.buf, NS, due_hl, row, seg.due_col, seg.due_end)
	end

	if seg.badge_col and seg.badge_end then
		hl(state.buf, NS, "TodoListNvimOverdue", row, seg.badge_col, seg.badge_end)
	end
end

---@param prefer_id string|nil
local function render(prefer_id)
	if not is_open() then
		return
	end

	local cursor_id = prefer_id
	if not cursor_id then
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		local idx = row - HEADER_LINES
		if idx >= 1 and idx <= #state.todos then
			cursor_id = state.todos[idx].id
		end
	end

	state.width = vim.api.nvim_win_get_width(state.win)
	state.todos = todo.sorted(todo.list())

	local lines = {
		" Todo List",
		"  a add  e edit  <CR>/t toggle  d due  x delete  ↑↓ move  q quit",
		" " .. string.rep("─", math.max(10, state.width - 2)),
	}

	---@type LineSegments[]
	local segments = {}

	if #state.todos == 0 then
		table.insert(lines, " (no todos — press a to add)")
	else
		for _, item in ipairs(state.todos) do
			local seg = format_line(item, state.width)
			table.insert(segments, seg)
			table.insert(lines, seg.text)
		end
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
	vim.api.nvim_buf_add_highlight(state.buf, NS, "TodoListNvimHeader", 0, 0, -1)
	vim.api.nvim_buf_add_highlight(state.buf, NS, "TodoListNvimHelp", 1, 0, -1)
	vim.api.nvim_buf_add_highlight(state.buf, NS, "TodoListNvimSeparator", 2, 0, -1)

	if #state.todos == 0 then
		vim.api.nvim_buf_add_highlight(state.buf, NS, "TodoListNvimHelp", 3, 0, -1)
	else
		for i, seg in ipairs(segments) do
			apply_row_highlights(i + HEADER_LINES - 1, seg)
		end
	end

	if #state.todos > 0 then
		local target_row = HEADER_LINES + 1
		if cursor_id then
			for i, item in ipairs(state.todos) do
				if item.id == cursor_id then
					target_row = i + HEADER_LINES
					break
				end
			end
		end
		local max_row = vim.api.nvim_buf_line_count(state.buf)
		vim.api.nvim_win_set_cursor(state.win, { math.min(target_row, max_row), 0 })
	end
end

---@return TodoItem|nil
local function todo_under_cursor()
	if not is_open() then
		return nil
	end
	local row = vim.api.nvim_win_get_cursor(state.win)[1]
	local idx = row - HEADER_LINES
	if idx < 1 or idx > #state.todos then
		return nil
	end
	return state.todos[idx]
end

---@return string
local function today_ymd()
	return os.date("%Y-%m-%d")
end

---@param ymd string
---@return integer|nil
local function parse_ymd(ymd)
	local y, m, d = ymd:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then
		return nil
	end
	return os.time({
		year = tonumber(y),
		month = tonumber(m),
		day = tonumber(d),
		hour = 12,
	})
end

---@param ts integer
---@return string
local function format_ymd(ts)
	return os.date("%Y-%m-%d", ts)
end

---Shift a YYYY-MM-DD by delta days. Empty/invalid starts from today.
---@param ymd string|nil
---@param delta integer
---@return string
local function shift_day(ymd, delta)
	local base = ymd
	if not base or base == "" or not parse_ymd(base) then
		base = today_ymd()
	end
	local ts = parse_ymd(base)
	return format_ymd(ts + (delta * 86400))
end

---Interactive due-date picker: ↑/↓ change day, Delete clears, Enter confirms, Esc cancels.
---@param opts { default: string|nil, title: string|nil }
---@param on_confirm fun(due: string|nil) due is nil on cancel; "" means clear/none
local function prompt_due_date(opts, on_confirm)
	local current = opts.default
	if current == nil then
		current = today_ymd()
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false

	local width = 44
	local height = 5
	local row = math.floor((vim.o.lines - height) / 2) + 2
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = opts.title or " due date ",
		title_pos = "center",
		zindex = 60,
	})

	local finished = false

	local function display_value()
		if current == "" then
			return "(none)"
		end
		return current
	end

	local function redraw()
		local lines = {
			"",
			"  " .. display_value(),
			"",
			"  ↑/↓ day   Del clear   Enter ok   Esc cancel",
		}
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
		local value_hl = current == "" and "TodoListNvimHelp" or "TodoListNvimDue"
		vim.api.nvim_buf_add_highlight(buf, NS, value_hl, 1, 0, -1)
		vim.api.nvim_buf_add_highlight(buf, NS, "TodoListNvimHelp", 3, 0, -1)
	end

	local function finish(result)
		if finished then
			return
		end
		finished = true
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		-- return focus to todo list if still open
		if is_open() then
			vim.api.nvim_set_current_win(state.win)
		end
		on_confirm(result)
	end

	local function map_picker(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, {
			buffer = buf,
			silent = true,
			nowait = true,
			desc = desc,
		})
	end

	map_picker("<Up>", function()
		current = shift_day(current, 1)
		redraw()
	end, "Next day")
	map_picker("k", function()
		current = shift_day(current, 1)
		redraw()
	end, "Next day")
	map_picker("<Down>", function()
		current = shift_day(current, -1)
		redraw()
	end, "Previous day")
	map_picker("j", function()
		current = shift_day(current, -1)
		redraw()
	end, "Previous day")
	map_picker("<Del>", function()
		current = ""
		redraw()
	end, "Clear due date")
	map_picker("<BS>", function()
		current = ""
		redraw()
	end, "Clear due date")
	map_picker("x", function()
		current = ""
		redraw()
	end, "Clear due date")
	map_picker("<CR>", function()
		finish(current)
	end, "Confirm")
	map_picker("<Esc>", function()
		finish(nil)
	end, "Cancel")
	map_picker("q", function()
		finish(nil)
	end, "Cancel")
	-- From empty, ↑/↓ restore today then step (shift_day already does this)
	map_picker("t", function()
		current = today_ymd()
		redraw()
	end, "Set to today")

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			if not finished then
				finished = true
				on_confirm(nil)
			end
		end,
	})

	redraw()
end

local function prompt_add()
	vim.ui.input({ prompt = "New todo: " }, function(title)
		if not title or vim.trim(title) == "" then
			return
		end
		prompt_due_date({
			default = today_ymd(),
			title = " due date (new) ",
		}, function(due)
			if due == nil then
				return -- cancelled
			end
			local ok, item_or_err = pcall(todo.add, title, due == "" and nil or due)
			if not ok then
				vim.notify(tostring(item_or_err), vim.log.levels.ERROR)
				return
			end
			render(item_or_err.id)
		end)
	end)
end

local function prompt_due()
	local item = todo_under_cursor()
	if not item then
		vim.notify("todo-list-nvim: move cursor onto a todo", vim.log.levels.WARN)
		return
	end
	prompt_due_date({
		default = item.due_at or today_ymd(),
		title = " due date ",
	}, function(due)
		if due == nil then
			return
		end
		local ok, err = pcall(todo.set_due, item.id, due)
		if not ok then
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return
		end
		render(item.id)
	end)
end

local function prompt_edit()
	local item = todo_under_cursor()
	if not item then
		vim.notify("todo-list-nvim: move cursor onto a todo", vim.log.levels.WARN)
		return
	end
	vim.ui.input({
		prompt = "Edit todo: ",
		default = item.title,
	}, function(title)
		if title == nil then
			return -- cancelled
		end
		local ok, err = pcall(todo.set_title, item.id, title)
		if not ok then
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return
		end
		render(item.id)
	end)
end

local function do_toggle()
	local item = todo_under_cursor()
	if not item then
		return
	end
	local ok, err = pcall(todo.toggle_complete, item.id)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return
	end
	render(item.id)
end

local function do_delete()
	local item = todo_under_cursor()
	if not item then
		return
	end
	local ok, err = pcall(todo.delete, item.id)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return
	end
	render()
end

local function map(lhs, rhs, desc)
	vim.keymap.set("n", lhs, rhs, {
		buffer = state.buf,
		silent = true,
		nowait = true,
		desc = desc,
	})
end

local function open_window()
	if is_open() then
		close()
		return
	end

	highlights.apply()

	local width = math.min(72, math.max(48, vim.o.columns - 8))
	local height = math.min(20, math.max(10, vim.o.lines - 8))
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	state.width = width
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "todo-list-nvim"

	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " todos ",
		title_pos = "center",
	})

	vim.wo[state.win].cursorline = true
	vim.wo[state.win].wrap = false

	map("q", close, "Close todo list")
	map("<Esc>", close, "Close todo list")
	map("a", prompt_add, "Add todo")
	map("e", prompt_edit, "Edit todo title")
	map("<CR>", do_toggle, "Toggle complete")
	map("t", do_toggle, "Toggle complete")
	map("d", prompt_due, "Set due date")
	map("x", do_delete, "Delete todo")
	map("r", function()
		render()
	end, "Refresh")

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = state.buf,
		once = true,
		callback = function()
			state.win = nil
			state.buf = nil
			state.todos = {}
		end,
	})

	render()
	if #state.todos > 0 then
		vim.api.nvim_win_set_cursor(state.win, { HEADER_LINES + 1, 0 })
	end
end

function M.toggle()
	open_window()
end

function M.refresh()
	if is_open() then
		render()
	end
end

function M.path_info()
	vim.notify("todo-list-nvim store: " .. config.path(), vim.log.levels.INFO)
end

return M
