local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local _plugins_dir = _dir:match("^(.*)/[^/]+/$") or (_dir .. "..")
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonDialog    = require("ui/widget/buttondialog")
local DataStorage     = require("datastorage")
local InfoMessage     = require("ui/widget/infomessage")
local LuaSettings     = require("luasettings")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _               = require("i18n")

require("i18n").extend(lrequire("i18n_fr"))

local Games = lrequire("games")
local NON_GAME_IDS   = Games.NON_GAME_IDS
local DEFAULT_ENABLED = Games.DEFAULT_ENABLED

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
-- and is one of ours rather than one of KOReader's own).
local function scanGamePlugins()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    if not ok then return {} end

    local games   = {}
    local ok2, iter, dir_obj = pcall(lfs.dir, _plugins_dir)
    if not ok2 or not iter then return {} end

    for entry in iter, dir_obj do
        if entry:match("%.koplugin$") then
            local pdir = _plugins_dir .. "/" .. entry
            local id   = entry:gsub("%.koplugin$", "")
            -- Shipping a common/ dir (game-common or sudoku-common) is what
            -- tells this fleet apart from KOReader's own plugins, none of
            -- which have one. checkers is the single game with no shared
            -- library of its own.
            local is_ours = id == "checkers"
                or lfs.attributes(pdir .. "/common", "mode") == "directory"
            local f = is_ours and io.open(pdir .. "/_meta.lua", "r")
            if f then
                local src  = f:read("*a"); f:close()
                local game = Games.parseMeta(src, id, NON_GAME_IDS)
                if game then games[#games + 1] = game end
            end
        end
    end

    return Games.sorted(games)
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
    -- settings_file must be a field, not a local. KOReader's PluginLoader
    -- reads instance.settings_file to decide whether to offer "Delete plugin
    -- settings", and removes the file itself (2026.07, PR #15240). Compute
    -- the path inline and the option never appears at all, leaving the file
    -- behind when the plugin is deleted.
    if not self.settings_file then
        self.settings_file = DataStorage:getSettingsDir() .. "/startmenu.lua"
    end
    if not self.settings then
        self.settings = LuaSettings:open(self.settings_file)
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
    return Games.isEnabled(gid, self:getSetting("enabled_games", nil), DEFAULT_ENABLED)
end

-- Toggles game `gid` and persists the full enabled-state map.
function StartMenu:toggleGame(gid)
    local saved = self:getSetting("enabled_games", nil)
    self:saveSetting("enabled_games",
        Games.toggled(self:getGamePlugins(), gid, saved, DEFAULT_ENABLED))
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
