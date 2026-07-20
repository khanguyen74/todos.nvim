if vim.g.loaded_todo_list_nvim then
  return
end
vim.g.loaded_todo_list_nvim = true

-- Thin bootstrap: full commands are registered in setup().
vim.api.nvim_create_user_command("Todo", function()
  local mod = require("todo-list-nvim")
  mod.ensure_setup()
  require("todo-list-nvim.ui").toggle()
end, { desc = "Toggle todo list floating window" })
