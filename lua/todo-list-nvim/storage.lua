local config = require("todo-list-nvim.config")

local M = {}

local SCHEMA_VERSION = 1

---@class TodoStore
---@field version integer
---@field todos TodoItem[]

---@return TodoStore
local function empty_store()
	return {
		version = SCHEMA_VERSION,
		todos = {},
	}
end

---@param path string
local function ensure_parent_dir(path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

---Minimal pretty JSON for the known store shape (human-friendly cloud diffs).
---@param store TodoStore
---@return string
local function encode_pretty(store)
	local lines = {
		"{",
		string.format('  "version": %d,', store.version or SCHEMA_VERSION),
		'  "todos": [',
	}

	local todos = store.todos or {}
	for i, todo in ipairs(todos) do
		local due = todo.due_at == nil and "null" or vim.json.encode(todo.due_at)
		local comma = i < #todos and "," or ""
		table.insert(lines, "    {")
		table.insert(lines, string.format('      "id": %s,', vim.json.encode(todo.id)))
		table.insert(lines, string.format('      "title": %s,', vim.json.encode(todo.title)))
		table.insert(lines, string.format('      "due_at": %s,', due))
		table.insert(lines, string.format('      "completed": %s,', todo.completed and "true" or "false"))
		table.insert(lines, string.format('      "created_at": %s,', vim.json.encode(todo.created_at)))
		table.insert(lines, string.format('      "updated_at": %s', vim.json.encode(todo.updated_at)))
		table.insert(lines, "    }" .. comma)
	end

	table.insert(lines, "  ]")
	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

---File mtime in seconds, or 0 if missing/unreadable.
---@return number
function M.mtime()
	local path = config.path()
	local stat = vim.uv.fs_stat(path)
	if not stat then
		return 0
	end
	return stat.mtime.sec + (stat.mtime.nsec or 0) / 1e9
end

---@return TodoStore
function M.load()
	local path = config.path()
	if vim.fn.filereadable(path) == 0 then
		return empty_store()
	end

	local lines = vim.fn.readfile(path)
	local raw = table.concat(lines, "\n")
	if raw == "" then
		return empty_store()
	end

	local ok, decoded = pcall(vim.json.decode, raw)
	if not ok or type(decoded) ~= "table" then
		vim.notify("todo-list-nvim: failed to parse " .. path .. "; starting empty", vim.log.levels.WARN)
		return empty_store()
	end

	if type(decoded.todos) ~= "table" then
		decoded.todos = {}
	end
	decoded.version = decoded.version or SCHEMA_VERSION

	for _, item in ipairs(decoded.todos) do
		if item.due_at == vim.NIL then
			item.due_at = nil
		end
	end

	return decoded
end

---@param store TodoStore
function M.save(store)
	local path = config.path()
	ensure_parent_dir(path)

	store.version = store.version or SCHEMA_VERSION
	local pretty = encode_pretty(store)

	local tmp = path .. ".tmp"
	local write_ok = pcall(vim.fn.writefile, vim.split(pretty, "\n", { plain = true }), tmp)
	if not write_ok then
		error("todo-list-nvim: failed to write " .. tmp)
	end

	local rename_ok, err = os.rename(tmp, path)
	if not rename_ok then
		pcall(os.remove, tmp)
		error("todo-list-nvim: failed to rename " .. tmp .. " -> " .. path .. ": " .. tostring(err))
	end
end

return M
