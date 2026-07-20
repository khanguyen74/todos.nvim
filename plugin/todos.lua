if vim.g.loaded_todos then
	return
end
vim.g.loaded_todos = true

-- Thin bootstrap: full commands are registered in setup().
vim.api.nvim_create_user_command("Todos", function()
	local mod = require("todos")
	mod.ensure_setup()
	require("todos.ui").toggle()
end, { desc = "Toggle todos floating window" })

vim.api.nvim_create_user_command("Todo", function()
	vim.cmd("Todos")
end, { desc = "Alias for :Todos" })
