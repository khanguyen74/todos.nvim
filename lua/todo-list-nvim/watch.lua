local config = require("todo-list-nvim.config")
local storage = require("todo-list-nvim.storage")

local M = {}

---@class WatchState
---@field fs_event uv.uv_fs_event_t|nil
---@field timer uv.uv_timer_t|nil
---@field last_mtime number
---@field on_change fun()
---@field debounce_ms integer

---@type WatchState|nil
local state = nil

local function stop_handles()
	if not state then
		return
	end
	if state.fs_event then
		pcall(function()
			state.fs_event:stop()
			state.fs_event:close()
		end)
		state.fs_event = nil
	end
	if state.timer then
		pcall(function()
			state.timer:stop()
			state.timer:close()
		end)
		state.timer = nil
	end
end

local function fire_if_changed()
	if not state then
		return
	end
	local mtime = storage.mtime()
	if mtime == state.last_mtime then
		return
	end
	state.last_mtime = mtime
	state.on_change()
end

---Watch the store file for external updates (other Neovim sessions / sync).
---Uses directory fs_event (rename-safe) with a light mtime poll fallback.
---@param on_change fun()
function M.start(on_change)
	M.stop()

	local path = config.path()
	local dir = vim.fn.fnamemodify(path, ":h")
	local basename = vim.fn.fnamemodify(path, ":t")
	if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	state = {
		fs_event = nil,
		timer = nil,
		last_mtime = storage.mtime(),
		on_change = on_change,
		debounce_ms = 150,
	}

	local pending = false
	local function schedule_check()
		if pending or not state then
			return
		end
		pending = true
		vim.defer_fn(function()
			pending = false
			fire_if_changed()
		end, state.debounce_ms)
	end

	local uv = vim.uv
	local handle = uv.new_fs_event()
	if handle then
		local started = pcall(function()
			handle:start(dir, {}, function(err, filename, _events)
				if err then
					return
				end
				-- filename may be nil on some platforms; check mtime anyway
				if filename == nil or filename == basename or filename == basename .. ".tmp" then
					vim.schedule(schedule_check)
				end
			end)
		end)
		if started then
			state.fs_event = handle
		else
			pcall(function()
				handle:close()
			end)
		end
	end

	-- Poll fallback for mounts where fs_event is unreliable (and as a safety net).
	local timer = uv.new_timer()
	if timer then
		timer:start(1000, 1000, function()
			vim.schedule(fire_if_changed)
		end)
		state.timer = timer
	end
end

function M.stop()
	stop_handles()
	state = nil
end

---Update tracked mtime after a local save.
function M.note_write()
	if state then
		state.last_mtime = storage.mtime()
	end
end

return M
