# todo-list-nvim

A personal todo list for Neovim. Todos are stored in a local JSON file so you can open them anytime while editing — and sync across machines by putting that file in a cloud drive folder (Dropbox, iCloud, Syncthing, Google Drive, etc.).

**Features**

- Due dates (`YYYY-MM-DD`)
- Overdue highlighting (computed — not stored)
- Completed / incomplete
- Floating window UI

## Requirements

- Neovim **0.9+** (`vim.json`, `vim.uv`)

## Install

### lazy.nvim (local development)

Point `dir` at this repo on your machine:

```lua
{
  dir = "~/Developments/todo-list-nvim", -- use your actual clone path
  name = "todo-list-nvim",
  config = function()
    require("todo-list-nvim").setup({})
  end,
}
```

### lazy.nvim (after cloning)

```bash
git clone <your-repo-url> ~/Developments/todo-list-nvim
```

Then use the same `dir = ...` snippet above. Once the project is on GitHub you can switch to:

```lua
{
  "your-username/todo-list-nvim",
  config = function()
    require("todo-list-nvim").setup({})
  end,
}
```

### Native packages (no plugin manager)

```bash
mkdir -p ~/.local/share/nvim/site/pack/local/start
ln -s ~/Developments/todo-list-nvim \
  ~/.local/share/nvim/site/pack/local/start/todo-list-nvim
```

In `init.lua`:

```lua
require("todo-list-nvim").setup({})
```

Restart Neovim (or run `:Lazy sync` if you use lazy.nvim), then try `:Todo`.

## Setup

**Default store** (local only):

`stdpath("data")/todo-list-nvim/todos.json`

On macOS/Linux that is usually:

`~/.local/share/nvim/todo-list-nvim/todos.json`

**Cloud-synced store** — set `path` to a file inside your cloud folder:

```lua
require("todo-list-nvim").setup({
  path = vim.fn.expand("~/Dropbox/nvim-todos/todos.json"),
})
```

Use `:TodoPath` anytime to print the active file path.

## Cloud sync (cloud drive)

The plugin does not talk to any cloud API. Sync is just: **one JSON file in a folder your cloud client already syncs**.

### Steps (any provider)

1. Create a folder in your cloud drive, e.g. `nvim-todos`.
2. On **each machine**, install the plugin and set `path` to that folder’s `todos.json` (see examples below).
3. Let the cloud client finish syncing before editing on another device.
4. Prefer editing from **one machine at a time**. If two devices write before sync finishes, **last write wins** and earlier changes can be lost.

Each time you run `:Todo`, the plugin fully re-reads `todos.json` from disk, so closing the float, editing elsewhere (or waiting for cloud sync), then opening again shows the latest list.

### Provider examples

**Dropbox**

```lua
path = vim.fn.expand("~/Dropbox/nvim-todos/todos.json")
```

**iCloud Drive (macOS)**

```lua
path = vim.fn.expand(
  "~/Library/Mobile Documents/com~apple~CloudDocs/nvim-todos/todos.json"
)
```

**Syncthing**

Point `path` at a file inside a synced folder, e.g.:

```lua
path = vim.fn.expand("~/Sync/nvim-todos/todos.json")
```

**Google Drive**

Use whatever local mount path your Drive client uses, e.g. Drive for desktop:

```lua
path = vim.fn.expand("~/Google Drive/My Drive/nvim-todos/todos.json")
```

(Exact folder names vary by OS and client.)

### Tips

- Keep the filename the same on every machine (`todos.json`).
- Avoid editing while the cloud client shows “syncing” or conflict copies (`todos (conflict).json`, etc.).
- Backups are free: the JSON is human-readable; copy or version it however you like.

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:Todo` | Toggle floating todo window |
| `:TodoAdd buy milk 2026-07-20` | Add a todo (optional trailing due date) |
| `:TodoList` | Print todos as notifications |
| `:TodoDue <id> [YYYY-MM-DD]` | Set due date (omit date to clear) |
| `:TodoToggle <id>` | Toggle completed by id |
| `:TodoPath` | Show path to `todos.json` |
| `:TodoEdit <id> new title` | Edit todo title by id |

### Floating window keys

| Key | Action |
|-----|--------|
| `a` | Add (due date defaults to **today**) |
| `e` | Edit title of the todo under the cursor |
| `<CR>` / `t` | Toggle complete |
| `d` | Set due date |
| `x` | Delete |
| `↑` / `↓` | Move between todos |
| `r` | Refresh |
| `q` / `<Esc>` | Close |

**Due date picker** (after `a` or `d`):

| Key | Action |
|-----|--------|
| `↑` / `k` | Next day |
| `↓` / `j` | Previous day |
| `Del` / `Backspace` / `x` | Clear due date → `(none)` |
| `t` | Jump to today |
| `Enter` | Confirm |
| `Esc` / `q` | Cancel |

Incomplete todos past their due date show a red **OVERDUE** badge; due dates sit in a separate column so they don’t stick to the title.

Colors use theme-linked highlight groups (`TodoListNvimCheckbox`, `TodoListNvimTitle`, `TodoListNvimTitleDone`, `TodoListNvimDue`, `TodoListNvimOverdue`, …). Override them after setup if you want custom colors:

```lua
vim.api.nvim_set_hl(0, "TodoListNvimDue", { fg = "#89b4fa" })
vim.api.nvim_set_hl(0, "TodoListNvimOverdue", { fg = "#f38ba8", bold = true })
```

## Data file format

```json
{
  "version": 1,
  "todos": [
    {
      "id": "20260719180000-1234",
      "title": "Ship plugin prototype",
      "due_at": "2026-07-20",
      "completed": false,
      "created_at": "2026-07-19T18:00:00Z",
      "updated_at": "2026-07-19T18:00:00Z"
    }
  ]
}
```

- `due_at` is `YYYY-MM-DD` or `null`.
- Overdue is **not** stored; it is derived when listing: incomplete and `due_at` before today.

## Multiple Neovim sessions

- Every `:Todo` open **fully re-reads** the JSON file from disk (no cache).
- Close the float → edit in another session or wait for cloud sync → open `:Todo` again to see updates.
- Press `r` while the float is open to re-read manually.
- Avoid **simultaneous writes** from two sessions — there is no merge; last save wins.

## License

MIT — see [LICENSE](LICENSE).
