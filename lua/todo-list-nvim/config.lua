local M = {}

---@class TodoListConfig
---@field path? string Absolute path to the todos JSON file (default: stdpath("data")/todo-list-nvim/todos.json)
---@field width? number Absolute columns if > 1, else fraction of vim.o.columns (0–1). nil → columns - 4
---@field height? number Absolute rows if > 1, else fraction of vim.o.lines (0–1). nil → lines - 4

---@type TodoListConfig
M.defaults = {
	path = vim.fn.stdpath("data") .. "/todo-list-nvim/todos.json",
	width = nil,
	height = nil,
}

---@type TodoListConfig
M.options = vim.deepcopy(M.defaults)

---@param opts TodoListConfig|nil
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
	M.options.path = vim.fn.expand(M.options.path)
end

---@return string
function M.path()
	return M.options.path
end

---@param value number|nil
---@param total integer
---@param fallback integer
---@param min_size integer
---@return integer
local function resolve_dim(value, total, fallback, min_size)
	local size
	if value == nil then
		size = fallback
	elseif value <= 1 then
		size = math.floor(total * value)
	else
		size = math.floor(value)
	end
	size = math.max(min_size, size)
	size = math.min(total, size)
	return size
end

---Compute float size from config at open time (respects terminal resize).
---@return integer width
---@return integer height
function M.window_size()
	local columns = vim.o.columns
	local lines = vim.o.lines
	local width = resolve_dim(M.options.width, columns, columns - 4, 40)
	local height = resolve_dim(M.options.height, lines, lines - 4, 10)
	return width, height
end

return M
