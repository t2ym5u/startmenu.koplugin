-- Game discovery and enable-state resolution.
--
-- Split out of main.lua because none of it needs KOReader: reading an id out of
-- a _meta.lua is string matching, and deciding whether a game shows in the menu
-- is a three-way answer (explicitly on, explicitly off, never touched) that is
-- easy to collapse into two by accident.

local Games = {}

-- Plugin IDs that are infrastructure, not games.
Games.NON_GAME_IDS = {
    startmenu     = true,
    pluginmanager = true,
    dashboard     = true,
    opdsdir       = true,
    _skeleton     = true,
}

-- Games shown by default when they are first discovered. Everything else a
-- player installs starts hidden, so the menu does not grow on its own.
Games.DEFAULT_ENABLED = {
    sudoku      = true,
    ["2048"]    = true,
    minesweeper = true,
    mastermind  = true,
}

-- Build { id, label } for one plugin. Returns nil for infrastructure.
--
-- `id` is the plugin directory's basename, and that is deliberate: this used
-- to read a `name` field out of the _meta.lua source, which none of these
-- plugins actually declares -- so the menu came up empty -- and which KOReader
-- 2026.03 (PR #15096) deprecated anyway, PluginLoader now overwriting it with
-- the directory name. `src` is the _meta.lua source, read only for the label.
function Games.parseMeta(src, id, non_game_ids)
    if type(id) ~= "string" or id == "" then return nil end
    if (non_game_ids or Games.NON_GAME_IDS)[id] then return nil end
    -- %f[%w] is a frontier pattern: it anchors to the start of the word, so
    -- `fullname =` is matched here and not some other key ending in "fullname".
    local fullname = type(src) == "string"
        and src:match('%f[%w]fullname%s*=[^"]*"([^"]*)"') or nil
    return { id = id, label = (fullname and #fullname > 0) and fullname or id }
end

-- Does game `gid` belong in the startup menu?
-- `saved` is the persisted id -> boolean map, or nil when the player has never
-- opened the game list. A game absent from a saved map is one installed since
-- the last toggle, so it falls back to the default rather than to "off".
function Games.isEnabled(gid, saved, defaults)
    defaults = defaults or Games.DEFAULT_ENABLED
    if not saved or saved[gid] == nil then
        return defaults[gid] == true
    end
    return saved[gid] == true
end

-- The map to persist after toggling `gid`: every known game gets an explicit
-- entry, so a later change to DEFAULT_ENABLED cannot silently move a game the
-- player has already made a decision about.
function Games.toggled(games, gid, saved, defaults)
    local next_state = {}
    for _, g in ipairs(games) do
        next_state[g.id] = Games.isEnabled(g.id, saved, defaults)
    end
    next_state[gid] = not next_state[gid]
    return next_state
end

-- Sort by the label the player actually reads, not by id.
function Games.sorted(games)
    table.sort(games, function(a, b) return a.label < b.label end)
    return games
end

return Games
