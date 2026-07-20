local M = {}

local AUGROUP = "todos-highlights"

local function link(name, target)
	vim.api.nvim_set_hl(0, name, { link = target, default = true })
end

---Theme-linked highlight groups for the floating UI.
function M.apply()
	link("TodosCheckbox", "Special")
	link("TodosTitle", "Normal")
	link("TodosDue", "Directory")
	link("TodosOverdue", "DiagnosticError")
	link("TodosHeader", "Title")
	link("TodosHelp", "Comment")
	link("TodosSeparator", "Comment")

	-- Completed titles: Comment colors + strikethrough (link alone can't add attrs)
	local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
	vim.api.nvim_set_hl(0, "TodosTitleDone", {
		fg = comment.fg,
		bg = comment.bg,
		ctermfg = comment.ctermfg,
		ctermbg = comment.ctermbg,
		italic = comment.italic,
		strikethrough = true,
		default = true,
	})
end

function M.setup()
	M.apply()
	vim.api.nvim_create_augroup(AUGROUP, { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = AUGROUP,
		callback = function()
			M.apply()
		end,
	})
end

return M
