local todo = require("todo-list-nvim.todo")
local config = require("todo-list-nvim.config")
local watch = require("todo-list-nvim.watch")

local M = {}

---@class UiState
---@field buf integer|nil
---@field win integer|nil
---@field todos TodoItem[]

---@type UiState
local state = {
	buf = nil,
	win = nil,
	todos = {},
}

local NS = vim.api.nvim_create_namespace("todo-list-nvim")

local function is_open()
	return state.win
		and vim.api.nvim_win_is_valid(state.win)
		and state.buf
		and vim.api.nvim_buf_is_valid(state.buf)
end

local function close()
	watch.stop()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
	state.todos = {}
end

---@param item TodoItem
---@return string
local function format_line(item)
	local mark = item.completed and "[x]" or "[ ]"
	local due = item.due_at and (" due:" .. item.due_at) or ""
	local flag = ""
	if todo.is_overdue(item) then
		flag = " OVERDUE"
	end
	return string.format("%s %s%s%s", mark, item.title, due, flag)
end

---@param prefer_id string|nil
local function render(prefer_id)
	if not is_open() then
		return
	end

	local cursor_id = prefer_id
	if not cursor_id then
		local row = vim.api.nvim_win_get_cursor(state.win)[1]
		local idx = row - 3
		if idx >= 1 and idx <= #state.todos then
			cursor_id = state.todos[idx].id
		end
	end

	state.todos = todo.sorted(todo.list())
	local lines = {
		" Todo List",
		"  a add  <CR>/t toggle  d due  x delete  q quit",
		" " .. string.rep("─", 48),
	}

	if #state.todos == 0 then
		table.insert(lines, " (no todos — press a to add)")
	else
		for _, item in ipairs(state.todos) do
			table.insert(lines, " " .. format_line(item))
		end
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
	for i, item in ipairs(state.todos) do
		local row = i + 2 -- header takes 3 lines (0-indexed: line index = i+2)
		if item.completed then
			vim.api.nvim_buf_add_highlight(state.buf, NS, "Comment", row, 0, -1)
		elseif todo.is_overdue(item) then
			vim.api.nvim_buf_add_highlight(state.buf, NS, "ErrorMsg", row, 0, -1)
		end
	end

	if #state.todos > 0 then
		local target_row = 4
		if cursor_id then
			for i, item in ipairs(state.todos) do
				if item.id == cursor_id then
					target_row = i + 3
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
	local idx = row - 3
	if idx < 1 or idx > #state.todos then
		return nil
	end
	return state.todos[idx]
end

local function prompt_add()
	vim.ui.input({ prompt = "New todo: " }, function(title)
		if not title or vim.trim(title) == "" then
			return
		end
		vim.ui.input({ prompt = "Due date YYYY-MM-DD (empty = none): " }, function(due)
			local ok, item_or_err = pcall(todo.add, title, due)
			if not ok then
				vim.notify(tostring(item_or_err), vim.log.levels.ERROR)
				return
			end
			watch.note_write()
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
	vim.ui.input({
		prompt = "Due date YYYY-MM-DD (empty = clear): ",
		default = item.due_at or "",
	}, function(due)
		if due == nil then
			return
		end
		local ok, err = pcall(todo.set_due, item.id, due)
		if not ok then
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return
		end
		watch.note_write()
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
	watch.note_write()
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
	watch.note_write()
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

local function start_watch()
	watch.start(function()
		if is_open() then
			render()
		end
	end)
end

local function open_window()
	if is_open() then
		close()
		return
	end

	local width = math.min(72, math.max(40, vim.o.columns - 8))
	local height = math.min(20, math.max(10, vim.o.lines - 8))
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

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
			watch.stop()
			state.win = nil
			state.buf = nil
			state.todos = {}
		end,
	})

	start_watch()
	render()
	if #state.todos > 0 then
		vim.api.nvim_win_set_cursor(state.win, { 4, 0 })
	end
end

function M.toggle()
	open_window()
end

function M.refresh()
	if is_open() then
		watch.note_write()
		render()
	end
end

function M.path_info()
	vim.notify("todo-list-nvim store: " .. config.path(), vim.log.levels.INFO)
end

return M
