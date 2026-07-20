local M = {}

---@class TodoListConfig
---@field path string Absolute path to the todos JSON file

---@type TodoListConfig
M.defaults = {
  path = vim.fn.stdpath("data") .. "/todo-list-nvim/todos.json",
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

return M
