local config = require("todos.config")
local todo = require("todos.todo")
local ui = require("todos.ui")
local highlights = require("todos.highlights")

local M = {}

local setup_done = false

local function notify_err(err)
  vim.notify(tostring(err), vim.log.levels.ERROR)
end

local function register_commands()
  vim.api.nvim_create_user_command("Todos", function()
    ui.toggle()
  end, { desc = "Toggle todo list floating window" })

  vim.api.nvim_create_user_command("TodosAdd", function(opts)
    local title = opts.args
    local due
    local date = title:match("%s(%d%d%d%d%-%d%d%-%d%d)%s*$")
    if date then
      due = date
      title = vim.trim(title:gsub("%s%d%d%d%d%-%d%d%-%d%d%s*$", ""))
    end
    local ok, err = pcall(todo.add, title, due)
    if not ok then
      notify_err(err)
      return
    end
    vim.notify("todos: added", vim.log.levels.INFO)
    ui.refresh()
  end, {
    nargs = "+",
    desc = "Add a todo (optional trailing YYYY-MM-DD due date)",
  })

  vim.api.nvim_create_user_command("TodosList", function()
    local items = todo.sorted(todo.list())
    if #items == 0 then
      vim.notify("todos: no todos", vim.log.levels.INFO)
      return
    end
    for _, item in ipairs(items) do
      local mark = item.completed and "[x]" or "[ ]"
      local due = item.due_at and (" due:" .. item.due_at) or ""
      local flag = todo.is_overdue(item) and " OVERDUE" or ""
      vim.notify(string.format("%s %s%s%s", mark, item.title, due, flag), vim.log.levels.INFO)
    end
  end, { desc = "Print todos to notifications" })

  vim.api.nvim_create_user_command("TodosToggle", function(opts)
    local id = opts.args
    if id == "" then
      notify_err("usage: TodosToggle <id>")
      return
    end
    local ok, err = pcall(todo.toggle_complete, id)
    if not ok then
      notify_err(err)
      return
    end
    ui.refresh()
  end, { nargs = 1, desc = "Toggle todo completed by id" })

  vim.api.nvim_create_user_command("TodosDue", function(opts)
    local parts = vim.split(opts.args, "%s+", { trimempty = true })
    if #parts < 1 then
      notify_err("usage: TodosDue <id> [YYYY-MM-DD]")
      return
    end
    local id = parts[1]
    local due = #parts == 1 and "" or parts[2]
    local ok, err = pcall(todo.set_due, id, due)
    if not ok then
      notify_err(err)
      return
    end
    ui.refresh()
  end, { nargs = "+", desc = "Set or clear due date: TodosDue <id> [YYYY-MM-DD]" })

  vim.api.nvim_create_user_command("TodosPath", function()
    ui.path_info()
  end, { desc = "Show path to todos.json" })

  vim.api.nvim_create_user_command("TodosEdit", function(opts)
    local parts = vim.split(opts.args, "%s+", { trimempty = true })
    if #parts < 2 then
      notify_err("usage: TodosEdit <id> <new title>")
      return
    end
    local id = parts[1]
    local title = vim.trim(opts.args:sub(#id + 1))
    local ok, err = pcall(todo.set_title, id, title)
    if not ok then
      notify_err(err)
      return
    end
    ui.refresh()
  end, { nargs = "+", desc = "Edit todo title: TodosEdit <id> <new title>" })

  -- Short alias
  vim.api.nvim_create_user_command("Todo", function()
    ui.toggle()
  end, { desc = "Alias for :Todos" })
end

---Ensure setup() has run (defaults if the user never called it).
function M.ensure_setup()
  if not setup_done then
    M.setup({})
  end
end

---@param opts TodosConfig|nil
function M.setup(opts)
  config.setup(opts)
  math.randomseed(os.time())
  highlights.setup()
  register_commands()
  setup_done = true
end

M.add = todo.add
M.list = todo.list
M.toggle_complete = todo.toggle_complete
M.set_due = todo.set_due
M.set_title = todo.set_title
M.delete = todo.delete
M.is_overdue = todo.is_overdue

return M
