local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local ButtonDialog    = require("ui/widget/buttondialog")
local DataStorage     = require("datastorage")
local InfoMessage     = require("ui/widget/infomessage")
local LuaSettings     = require("luasettings")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _               = require("gettext")

-- ---------------------------------------------------------------------------
-- All available games, in display order.
-- `id` must match the target plugin's `name` field exactly.
-- ---------------------------------------------------------------------------

local ALL_GAMES = {
    { id = "sudoku",      label = _("Sudoku") },
    { id = "2048",        label = _("2048") },
    { id = "minesweeper", label = _("Minesweeper") },
    { id = "mastermind",  label = _("Mastermind") },
    { id = "futoshiki",   label = _("Futoshiki") },
    { id = "hitori",      label = _("Hitori") },
    { id = "kakuro",      label = _("Kakuro") },
    { id = "kenken",      label = _("KenKen") },
    { id = "nonogram",    label = _("Nonogram") },
    { id = "numberlink",  label = _("NumberLink") },
    { id = "nurikabe",    label = _("Nurikabe") },
}

-- Games shown by default (id → true).
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
}

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

-- Safe getter: correctly handles stored `false` values (avoids the
-- `v ~= nil and v or default` pitfall where false falls through to default).
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

-- Toggles game `gid` and writes the full state back to disk.
function StartMenu:toggleGame(gid)
    local new_state = {}
    for _, g in ipairs(ALL_GAMES) do
        new_state[g.id] = self:isGameEnabled(g.id)
    end
    new_state[gid] = not new_state[gid]
    self:saveSetting("enabled_games", new_state)
end

-- Returns the list of { id, label } entries that are currently enabled.
function StartMenu:enabledGames()
    local result = {}
    for _, g in ipairs(ALL_GAMES) do
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
    -- ReaderUI sets self.ui.document; FileManager does not.
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

    for _, g in ipairs(ALL_GAMES) do
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
    -- Prevent a second dialog if one is already open.
    if self._dialog then return end

    local games = self:enabledGames()

    -- Nothing to offer if every game is disabled.
    if #games == 0 then return end

    local dialog  -- forward declaration; captured by button closures below

    local buttons = {
        -- "Read" always occupies the first row.
        {
            {
                text     = _("Read"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
        },
    }

    for _, g in ipairs(games) do
        local gid    = g.id
        local glabel = g.label
        buttons[#buttons + 1] = {
            {
                text     = glabel,
                callback = function()
                    UIManager:close(dialog)
                    -- Small delay so the dialog repaint completes before the
                    -- game screen is pushed on top.
                    UIManager:scheduleIn(0.1, function()
                        self:launchGame(gid, glabel)
                    end)
                end,
            },
        }
    end

    dialog = ButtonDialog:new{
        title              = _("What would you like to do?"),
        buttons            = buttons,
        -- Clear our reference when the dialog is closed by any means.
        dismissable        = true,
    }

    -- Keep a reference so we can guard against duplicates and close externally.
    self._dialog = dialog

    -- Wrap close to nil out our reference regardless of how the dialog closes.
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

-- Plugins are stored by name on the parent UI widget by KOReader's plugin
-- loader, so self.ui["sudoku"] is the live Sudoku plugin instance, etc.
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
