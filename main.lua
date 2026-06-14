local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local _plugins_dir = _dir:match("^(.*)/[^/]+/$") or (_dir .. "..")
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local ButtonDialog    = require("ui/widget/buttondialog")
local DataStorage     = require("datastorage")
local InfoMessage     = require("ui/widget/infomessage")
local LuaSettings     = require("luasettings")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _               = require("gettext")

-- Plugin IDs that are infrastructure, not games; excluded from scanning.
local NON_GAME_IDS = {
    startmenu     = true,
    pluginmanager = true,
    _skeleton     = true,
}

-- Games shown by default when they are first discovered (id → true).
-- All other discovered games default to disabled.
local DEFAULT_ENABLED = {
    sudoku      = true,
    ["2048"]    = true,
    minesweeper = true,
    mastermind  = true,
}

-- ---------------------------------------------------------------------------
-- StartMenu plugin
-- ---------------------------------------------------------------------------

local StartMenu = WidgetContainer:extend{
    name        = "startmenu",
    is_doc_only = false,
    -- _game_plugins : cached result of the last filesystem scan
}

-- ---------------------------------------------------------------------------
-- Game-plugin discovery
-- ---------------------------------------------------------------------------

-- Scan the plugins directory and return a sorted list of { id, label } for
-- every installed game plugin (i.e. any *.koplugin that is not in NON_GAME_IDS
-- and has a readable _meta.lua with a name field).
local function scanGamePlugins()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    if not ok then return {} end

    local games   = {}
    local ok2, iter, dir_obj = pcall(lfs.dir, _plugins_dir)
    if not ok2 or not iter then return {} end

    for entry in iter, dir_obj do
        if entry:match("%.koplugin$") then
            local meta_path = _plugins_dir .. "/" .. entry .. "/_meta.lua"
            local f = io.open(meta_path, "r")
            if f then
                local src      = f:read("*a"); f:close()
                local name     = src:match('name%s*=%s*"([^"]+)"')
                local fullname = src:match('fullname%s*=[^"]*"([^"]*)"')
                if name and not NON_GAME_IDS[name] then
                    games[#games + 1] = { id = name, label = fullname or name }
                end
            end
        end
    end

    table.sort(games, function(a, b) return a.label < b.label end)
    return games
end

-- Returns the cached game list, rebuilding it lazily on first access.
-- The cache lives for one KOReader session; plugins installed/removed during
-- a session require a restart anyway to take effect.
function StartMenu:getGamePlugins()
    if not self._game_plugins then
        self._game_plugins = scanGamePlugins()
    end
    return self._game_plugins
end

-- ---------------------------------------------------------------------------
-- Settings helpers
-- ---------------------------------------------------------------------------

function StartMenu:ensureSettings()
    if not self.settings then
        self.settings = LuaSettings:open(
            DataStorage:getSettingsDir() .. "/startmenu.lua"
        )
    end
end

function StartMenu:getSetting(key, default)
    self:ensureSettings()
    local v = self.settings:readSetting(key)
    if v == nil then return default end
    return v
end

function StartMenu:saveSetting(key, value)
    self:ensureSettings()
    self.settings:saveSetting(key, value)
    self.settings:flush()
end

-- ---------------------------------------------------------------------------
-- Game-enable helpers
-- ---------------------------------------------------------------------------

-- Returns true if game `gid` should appear in the startup menu.
-- Falls back to DEFAULT_ENABLED for games that have never been toggled.
function StartMenu:isGameEnabled(gid)
    local saved = self:getSetting("enabled_games", nil)
    if not saved then
        return DEFAULT_ENABLED[gid] == true
    end
    if saved[gid] == nil then
        return DEFAULT_ENABLED[gid] == true
    end
    return saved[gid] == true
end

-- Toggles game `gid` and persists the full enabled-state map.
function StartMenu:toggleGame(gid)
    local new_state = {}
    for _, g in ipairs(self:getGamePlugins()) do
        new_state[g.id] = self:isGameEnabled(g.id)
    end
    new_state[gid] = not new_state[gid]
    self:saveSetting("enabled_games", new_state)
end

-- Returns the list of { id, label } entries that are currently enabled.
function StartMenu:enabledGames()
    local result = {}
    for _, g in ipairs(self:getGamePlugins()) do
        if self:isGameEnabled(g.id) then
            result[#result + 1] = g
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Plugin lifecycle
-- ---------------------------------------------------------------------------

function StartMenu:init()
    self:ensureSettings()
    self.ui.menu:registerToMainMenu(self)

    -- Only fire in the FileManager context (no open document).
    if not self.ui.document and self:getSetting("enabled", true) then
        UIManager:scheduleIn(0.5, function()
            self:showStartupMenu()
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Main menu entry (Tools → Startup Menu)
-- ---------------------------------------------------------------------------

function StartMenu:addToMainMenu(menu_items)
    local sub = {
        {
            text     = _("Show startup menu now"),
            callback = function() self:showStartupMenu() end,
        },
        {
            text         = _("Enable on startup"),
            checked_func = function() return self:getSetting("enabled", true) end,
            callback     = function()
                self:saveSetting("enabled", not self:getSetting("enabled", true))
            end,
        },
        {
            text    = _("Games to show:"),
            enabled = false,
        },
    }

    for _, g in ipairs(self:getGamePlugins()) do
        local gid = g.id
        sub[#sub + 1] = {
            text         = g.label,
            checked_func = function() return self:isGameEnabled(gid) end,
            callback     = function() self:toggleGame(gid) end,
        }
    end

    menu_items.startmenu = {
        text           = _("Startup Menu"),
        sorting_hint   = "tools",
        sub_item_table = sub,
    }
end

-- ---------------------------------------------------------------------------
-- Startup dialog
-- ---------------------------------------------------------------------------

function StartMenu:showStartupMenu()
    if self._dialog then return end

    local games = self:enabledGames()
    if #games == 0 then return end

    local dialog

    local buttons = {
        {{
            text     = _("Read"),
            callback = function() UIManager:close(dialog) end,
        }},
    }

    for _, g in ipairs(games) do
        local gid    = g.id
        local glabel = g.label
        buttons[#buttons + 1] = {{
            text     = glabel,
            callback = function()
                UIManager:close(dialog)
                UIManager:scheduleIn(0.1, function()
                    self:launchGame(gid, glabel)
                end)
            end,
        }}
    end

    dialog = ButtonDialog:new{
        title       = _("What would you like to do?"),
        buttons     = buttons,
        dismissable = true,
    }

    self._dialog = dialog

    local orig_free = dialog.free
    dialog.free = function(d)
        self._dialog = nil
        if orig_free then orig_free(d) end
    end

    UIManager:show(dialog)
end

-- Close the startup dialog programmatically (e.g. from a game's onScreenClosed).
function StartMenu:closeStartupMenu()
    if self._dialog then
        UIManager:close(self._dialog)
    end
end

-- ---------------------------------------------------------------------------
-- Game launcher
-- ---------------------------------------------------------------------------

function StartMenu:launchGame(gid, glabel)
    local plugin = self.ui[gid]
    if plugin and type(plugin.showGame) == "function" then
        plugin:showGame()
    else
        UIManager:show(InfoMessage:new{
            text    = string.format(_("%s is not installed or not active."), glabel),
            timeout = 3,
        })
    end
end

return StartMenu
