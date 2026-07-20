local storage = require("todos.storage")

local M = {}

---@class TodoItem
---@field id string
---@field title string
---@field due_at string|nil YYYY-MM-DD or nil
---@field completed boolean
---@field created_at string ISO 8601 UTC
---@field updated_at string ISO 8601 UTC

---@return string
local function now_iso()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

---@return string
local function today_local()
	return os.date("%Y-%m-%d")
end

---@return string
local function new_id()
	return string.format("%s-%04d", os.date("!%Y%m%d%H%M%S"), math.random(0, 9999))
end

---@param due_at string|nil
---@return boolean
local function valid_due_date(due_at)
	if due_at == nil or due_at == "" then
		return true
	end
	return due_at:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

---Past due is derived: incomplete + due_at before today (local date).
---@param todo TodoItem
---@return boolean
function M.is_overdue(todo)
	if todo.completed or not todo.due_at or todo.due_at == "" then
		return false
	end
	return todo.due_at < today_local()
end

---@return TodoItem[]
function M.list()
	return storage.load().todos
end

---@param title string
---@param due_at string|nil
---@return TodoItem
function M.add(title, due_at)
	title = vim.trim(title or "")
	if title == "" then
		error("todos: title is required")
	end
	if due_at == "" then
		due_at = nil
	end
	if not valid_due_date(due_at) then
		error("todos: due_at must be YYYY-MM-DD")
	end

	local store = storage.load()
	local ts = now_iso()
	---@type TodoItem
	local item = {
		id = new_id(),
		title = title,
		due_at = due_at,
		completed = false,
		created_at = ts,
		updated_at = ts,
	}
	table.insert(store.todos, item)
	storage.save(store)
	return item
end

---@param id string
---@return TodoItem|nil
function M.find(id)
	for _, todo in ipairs(storage.load().todos) do
		if todo.id == id then
			return todo
		end
	end
	return nil
end

---@param id string
---@return TodoItem
function M.toggle_complete(id)
	local store = storage.load()
	for _, todo in ipairs(store.todos) do
		if todo.id == id then
			todo.completed = not todo.completed
			todo.updated_at = now_iso()
			storage.save(store)
			return todo
		end
	end
	error("todos: todo not found: " .. tostring(id))
end

---@param id string
---@param due_at string|nil
---@return TodoItem
function M.set_due(id, due_at)
	if due_at == "" then
		due_at = nil
	end
	if not valid_due_date(due_at) then
		error("todos: due_at must be YYYY-MM-DD")
	end

	local store = storage.load()
	for _, todo in ipairs(store.todos) do
		if todo.id == id then
			todo.due_at = due_at
			todo.updated_at = now_iso()
			storage.save(store)
			return todo
		end
	end
	error("todos: todo not found: " .. tostring(id))
end

---@param id string
---@param title string
---@return TodoItem
function M.set_title(id, title)
	title = vim.trim(title or "")
	if title == "" then
		error("todos: title is required")
	end

	local store = storage.load()
	for _, todo in ipairs(store.todos) do
		if todo.id == id then
			todo.title = title
			todo.updated_at = now_iso()
			storage.save(store)
			return todo
		end
	end
	error("todos: todo not found: " .. tostring(id))
end

---@param id string
---@return TodoItem
function M.delete(id)
	local store = storage.load()
	for i, todo in ipairs(store.todos) do
		if todo.id == id then
			table.remove(store.todos, i)
			storage.save(store)
			return todo
		end
	end
	error("todos: todo not found: " .. tostring(id))
end

---Sort: incomplete first, then overdue, then by due_at, then title.
---@param todos TodoItem[]
---@return TodoItem[]
function M.sorted(todos)
	local copy = vim.deepcopy(todos)
	table.sort(copy, function(a, b)
		if a.completed ~= b.completed then
			return not a.completed
		end
		local a_over = M.is_overdue(a)
		local b_over = M.is_overdue(b)
		if a_over ~= b_over then
			return a_over
		end
		local a_due = a.due_at or "9999-12-31"
		local b_due = b.due_at or "9999-12-31"
		if a_due ~= b_due then
			return a_due < b_due
		end
		return a.title < b.title
	end)
	return copy
end

return M
