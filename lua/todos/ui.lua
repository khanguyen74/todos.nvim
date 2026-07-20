local todo = require("todos.todo")
local config = require("todos.config")
local highlights = require("todos.highlights")

local M = {}

---@class UiState
---@field buf integer|nil
---@field win integer|nil
---@field todos TodoItem[]
---@field width integer
---@field line_todo_id table<integer, string> 1-based buffer row → todo id
---@field id_first_row table<string, integer> todo id → first 1-based buffer row

---@type UiState
local state = {
	buf = nil,
	win = nil,
	todos = {},
	width = 72,
	line_todo_id = {},
	id_first_row = {},
}

local NS = vim.api.nvim_create_namespace("todos")

local HEADER_LINES = 3
local DUE_COL_WIDTH = 15 -- "due YYYY-MM-DD"
local BADGE = "OVERDUE"
local BADGE_WIDTH = #BADGE + 4 -- "  OVERDUE"
local RIGHT_COL_WIDTH = DUE_COL_WIDTH + BADGE_WIDTH
local PREFIX = " [ ]  " -- display width of checkbox prefix (same for [x])
local PREFIX_WIDTH = vim.fn.strdisplaywidth(PREFIX)

local function is_open()
	return state.win and vim.api.nvim_win_is_valid(state.win) and state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
	state.todos = {}
	state.line_todo_id = {}
	state.id_first_row = {}
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

---Wrap string into chunks that each fit within max_width display cells (no ellipsis).
---Prefers breaking at spaces when possible.
---@param s string
---@param max_width integer
---@return string[]
local function wrap_text(s, max_width)
	if max_width < 1 then
		max_width = 1
	end
	if s == "" then
		return { "" }
	end

	local chunks = {}
	local chars = vim.fn.strchars(s)
	local i = 0
	while i < chars do
		-- skip leading spaces on new lines (except we keep them only within a chunk)
		while i < chars and vim.fn.strcharpart(s, i, 1) == " " do
			i = i + 1
		end
		if i >= chars then
			break
		end

		local hi = chars - i
		local best = 1
		local left, right = 1, hi
		while left <= right do
			local mid = math.floor((left + right) / 2)
			local part = vim.fn.strcharpart(s, i, mid)
			if vim.fn.strdisplaywidth(part) <= max_width then
				best = mid
				left = mid + 1
			else
				right = mid - 1
			end
		end
		if best < 1 then
			best = 1
		end

		-- prefer last space within the chunk (word wrap)
		local chunk = vim.fn.strcharpart(s, i, best)
		if i + best < chars then
			local break_at = nil
			for j = best, 1, -1 do
				if vim.fn.strcharpart(s, i + j - 1, 1) == " " then
					break_at = j - 1 -- exclude the space
					break
				end
			end
			if break_at and break_at > 0 then
				best = break_at
				chunk = vim.fn.strcharpart(s, i, best)
			end
		end

		table.insert(chunks, chunk)
		i = i + best
		-- consume the space we broke on
		if i < chars and vim.fn.strcharpart(s, i, 1) == " " then
			i = i + 1
		end
	end

	if #chunks == 0 then
		return { "" }
	end
	return chunks
end

---@class LineSegments
---@field text string
---@field checkbox_col integer|nil 0-based byte start
---@field checkbox_end integer|nil
---@field title_col integer|nil
---@field title_end integer|nil
---@field due_col integer|nil
---@field due_end integer|nil
---@field badge_col integer|nil
---@field badge_end integer|nil
---@field overdue boolean
---@field completed boolean

---Two-column block: title wraps on the left; due/OVERDUE fixed on first line right column.
---@param item TodoItem
---@param width integer
---@return LineSegments[]
local function format_item(item, width)
	local mark = item.completed and "[x]" or "[ ]"
	local overdue = todo.is_overdue(item)
	local due_text = item.due_at and ("due " .. item.due_at) or ""
	local badge_text = overdue and BADGE or ""

	local prefix = " " .. mark .. "  "
	local title_width = math.max(4, width - PREFIX_WIDTH - RIGHT_COL_WIDTH)
	local title_chunks = wrap_text(item.title, title_width)
	if #title_chunks == 0 then
		title_chunks = { "" }
	end

	local cont_indent = string.rep(" ", PREFIX_WIDTH)
	---@type LineSegments[]
	local segs = {}

	for i, chunk in ipairs(title_chunks) do
		local is_first = i == 1
		local left
		local checkbox_col, checkbox_end, title_col, title_end
		local due_col, due_end, badge_col, badge_end

		if is_first then
			left = prefix .. pad_right(chunk, title_width)
			checkbox_col = 1
			checkbox_end = checkbox_col + #mark
			title_col = #prefix
			title_end = title_col + #chunk

			-- fixed right column always starts after left column
			local right_start = #left
			local due_padded = pad_right(due_text, DUE_COL_WIDTH)
			left = left .. due_padded
			if due_text ~= "" then
				due_col = right_start
				due_end = right_start + #due_text
			end
			if badge_text ~= "" then
				left = left .. "  " .. badge_text
				badge_col = right_start + DUE_COL_WIDTH + 2
				badge_end = badge_col + #badge_text
			else
				-- keep column width consistent when no badge
				left = left .. string.rep(" ", BADGE_WIDTH)
			end
		else
			left = cont_indent .. chunk
			title_col = #cont_indent
			title_end = title_col + #chunk
		end

		table.insert(segs, {
			text = left,
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
		})
	end

	return segs
end

---@param row integer 0-based
---@param seg LineSegments
local function apply_row_highlights(row, seg)
	local hl = vim.api.nvim_buf_add_highlight
	if seg.checkbox_col and seg.checkbox_end then
		hl(state.buf, NS, "TodosCheckbox", row, seg.checkbox_col, seg.checkbox_end)
	end

	if seg.title_col and seg.title_end and seg.title_end > seg.title_col then
		local title_hl = seg.completed and "TodosTitleDone" or "TodosTitle"
		hl(state.buf, NS, title_hl, row, seg.title_col, seg.title_end)
	end

	if seg.due_col and seg.due_end then
		local due_hl = (seg.overdue and not seg.completed) and "TodosOverdue" or "TodosDue"
		hl(state.buf, NS, due_hl, row, seg.due_col, seg.due_end)
	end

	if seg.badge_col and seg.badge_end then
		hl(state.buf, NS, "TodosOverdue", row, seg.badge_col, seg.badge_end)
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
		cursor_id = state.line_todo_id[row]
	end

	state.width = vim.api.nvim_win_get_width(state.win)
	state.todos = todo.sorted(todo.list())
	state.line_todo_id = {}
	state.id_first_row = {}

	local lines = {
		" Todos",
		"  a add  e edit  <CR>/t toggle  d due  x delete  ↑↓ move  q quit",
		" " .. string.rep("─", math.max(10, state.width - 2)),
	}

	---@type LineSegments[]
	local segments = {}
	---@type integer[] 0-based row for each segment
	local segment_rows = {}

	if #state.todos == 0 then
		table.insert(lines, " (no todos — press a to add)")
	else
		for _, item in ipairs(state.todos) do
			local item_segs = format_item(item, state.width)
			local first_row = #lines + 1 -- 1-based
			state.id_first_row[item.id] = first_row
			for _, seg in ipairs(item_segs) do
				local row_1 = #lines + 1
				state.line_todo_id[row_1] = item.id
				table.insert(lines, seg.text)
				table.insert(segments, seg)
				table.insert(segment_rows, row_1 - 1)
			end
		end
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
	vim.api.nvim_buf_add_highlight(state.buf, NS, "TodosHeader", 0, 0, -1)
	vim.api.nvim_buf_add_highlight(state.buf, NS, "TodosHelp", 1, 0, -1)
	vim.api.nvim_buf_add_highlight(state.buf, NS, "TodosSeparator", 2, 0, -1)

	if #state.todos == 0 then
		vim.api.nvim_buf_add_highlight(state.buf, NS, "TodosHelp", 3, 0, -1)
	else
		for i, seg in ipairs(segments) do
			apply_row_highlights(segment_rows[i], seg)
		end
	end

	if #state.todos > 0 then
		local target_row = state.id_first_row[state.todos[1].id] or (HEADER_LINES + 1)
		if cursor_id and state.id_first_row[cursor_id] then
			target_row = state.id_first_row[cursor_id]
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
	local id = state.line_todo_id[row]
	if not id then
		return nil
	end
	for _, item in ipairs(state.todos) do
		if item.id == id then
			return item
		end
	end
	return nil
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
		local value_hl = current == "" and "TodosHelp" or "TodosDue"
		vim.api.nvim_buf_add_highlight(buf, NS, value_hl, 1, 0, -1)
		vim.api.nvim_buf_add_highlight(buf, NS, "TodosHelp", 3, 0, -1)
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
		vim.notify("todos: move cursor onto a todo", vim.log.levels.WARN)
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
		vim.notify("todos: move cursor onto a todo", vim.log.levels.WARN)
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

	local width, height = config.window_size()
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	state.width = width
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "todos"

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
			state.line_todo_id = {}
			state.id_first_row = {}
		end,
	})

	render()
	if #state.todos > 0 then
		local first = state.id_first_row[state.todos[1].id] or (HEADER_LINES + 1)
		vim.api.nvim_win_set_cursor(state.win, { first, 0 })
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
	vim.notify("todos store: " .. config.path(), vim.log.levels.INFO)
end

return M
