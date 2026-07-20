# todos.nvim

A personal todo list for Neovim. Todos live in a local JSON file so you can open them anytime — and sync across machines by putting that file in a cloud drive folder (Dropbox, iCloud, Syncthing, Google Drive, etc.).

**Features**

- Due dates (`YYYY-MM-DD`)
- Overdue highlighting (computed — not stored)
- Completed / incomplete
- Floating window UI (near-full width; titles wrap in a left column, due/OVERDUE on the right)

## Requirements

- Neovim **0.9+** (`vim.json`, `vim.uv`)

## Install

### lazy.nvim

```lua
{
  "khanguyen74/todos.nvim",
  config = function()
    require("todos").setup({})
  end,
}
```

## Setup

Default store: `stdpath("data")/todos.nvim/todos.json`  
(usually `~/.local/share/nvim/todos.nvim/todos.json`)

```lua
require("todos").setup({
  -- Optional cloud-synced path
  -- path = vim.fn.expand("~/Dropbox/nvim-todos/todos.json"),

  -- Float size: nil = nearly full; 0–1 = fraction; >1 = absolute
  width = 0.9,
  height = 0.8,
})
```

Use `:TodosPath` to print the active file path.

## Cloud sync

Point `path` at a file inside a synced folder on every machine. Prefer editing one device at a time (last write wins). Each `:Todos` open fully re-reads the JSON from disk.

**Examples:** Dropbox `~/Dropbox/nvim-todos/todos.json`, iCloud `~/Library/Mobile Documents/com~apple~CloudDocs/nvim-todos/todos.json`, Syncthing/Google Drive similarly.

## Usage

| Command | Description |
|---------|-------------|
| `:Todos` | Toggle floating window (`:Todo` is an alias) |
| `:TodosAdd buy milk 2026-07-20` | Add (optional trailing due date) |
| `:TodosList` | Print todos |
| `:TodosDue <id> [YYYY-MM-DD]` | Set due date (omit date to clear) |
| `:TodosToggle <id>` | Toggle completed by id |
| `:TodosEdit <id> new title` | Edit title by id |
| `:TodosPath` | Show path to `todos.json` |

### Floating window keys

| Key | Action |
|-----|--------|
| `a` | Add (due defaults to today) |
| `e` | Edit title |
| `<CR>` / `t` | Toggle complete |
| `d` | Set due date |
| `x` | Delete |
| `↑` / `↓` | Move |
| `r` | Refresh (re-read file) |
| `q` / `<Esc>` | Close |

**Due date picker** (`a` or `d`): `↑`/`↓` change day · `Del`/`BS`/`x` clear · `t` today · Enter confirm · Esc cancel

Highlight groups: `TodosCheckbox`, `TodosTitle`, `TodosTitleDone`, `TodosDue`, `TodosOverdue`, …

```lua
vim.api.nvim_set_hl(0, "TodosDue", { fg = "#89b4fa" })
```

## License

MIT — see [LICENSE](LICENSE).
