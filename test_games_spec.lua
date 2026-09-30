-- Whether a game appears in the startup menu is a three-way answer -- the
-- player turned it on, the player turned it off, or the player has never seen
-- it -- and the third case is the one that quietly collapses into "off".
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.path = DIR .. "?.lua;" .. package.path

describe("Games.parseMeta", function()
    local Games

    setup(function()
        Games = require("games")
    end)

    it("takes the id from the directory, not from the _meta.lua source", function()
        -- KOReader 2026.03 (PR #15096) made the directory name the plugin id
        -- and deprecated _meta.lua's `name`. A stale `name` in the source must
        -- not win over the directory it was found in.
        local g = Games.parseMeta([[
            return {
                name = "killer_sudoku",
                fullname = _("Killer Sudoku"),
            }
        ]], "sudokukiller")
        assert.are.equal("sudokukiller", g.id)
        assert.are.equal("Killer Sudoku", g.label)
    end)

    it("reads the label out of a _meta.lua", function()
        local g = Games.parseMeta([[
            return {
                fullname = _("Sokoban"),
                description = _("Push the crates onto the targets."),
            }
        ]], "sokoban")
        assert.are.equal("sokoban", g.id)
        assert.are.equal("Sokoban", g.label)
    end)

    it("reads a fullname that is a plain string, not a _() call", function()
        local g = Games.parseMeta('return { fullname = "Tower of Hanoi" }', "hanoi")
        assert.are.equal("Tower of Hanoi", g.label)
    end)

    it("falls back to the id when there is no fullname", function()
        local g = Games.parseMeta('return { description = _("x") }', "hanoi")
        assert.are.equal("hanoi", g.label)
    end)

    it("falls back to the id rather than showing a blank row", function()
        local g = Games.parseMeta('return { fullname = _("") }', "hanoi")
        assert.are.equal("hanoi", g.label)
    end)

    it("still labels a game whose _meta.lua is unreadable", function()
        -- The directory alone is enough to launch it; only the label is lost.
        local g = Games.parseMeta(nil, "hanoi")
        assert.are.equal("hanoi", g.id)
        assert.are.equal("hanoi", g.label)
    end)

    it("ignores infrastructure plugins", function()
        assert.is_nil(Games.parseMeta('return { fullname = "Start Menu" }', "startmenu"))
        assert.is_nil(Games.parseMeta("", "pluginmanager"))
        assert.is_nil(Games.parseMeta("", "dashboard"))
        assert.is_nil(Games.parseMeta("", "opdsdir"))
        assert.is_nil(Games.parseMeta("", "_skeleton"))
    end)

    it("ignores a directory with no usable id", function()
        assert.is_nil(Games.parseMeta('return { fullname = "x" }', nil))
        assert.is_nil(Games.parseMeta('return { fullname = "x" }', ""))
    end)

    it("takes the ids of the real plugins as written", function()
        -- 2048's id is numeric-looking and quoted as a key elsewhere; make sure
        -- nothing along the way turns it into a number or drops it.
        local g = Games.parseMeta('return { fullname = _("2048") }', "2048")
        assert.are.equal("2048", g.id)
        assert.are.equal("string", type(g.id))
    end)
end)

describe("Games.isEnabled", function()
    local Games
    local DEFAULTS = { sudoku = true, ["2048"] = true }

    setup(function()
        Games = require("games")
    end)

    it("shows only the default games before the player has touched anything", function()
        assert.is_true(Games.isEnabled("sudoku", nil, DEFAULTS))
        assert.is_false(Games.isEnabled("hanoi", nil, DEFAULTS))
    end)

    it("obeys an explicit choice, in both directions", function()
        local saved = { sudoku = false, hanoi = true }
        assert.is_false(Games.isEnabled("sudoku", saved, DEFAULTS))
        assert.is_true(Games.isEnabled("hanoi", saved, DEFAULTS))
    end)

    it("falls back to the default for a game installed since the last toggle", function()
        -- The saved map only lists games that existed when it was written; a
        -- newly installed one must not be read as "the player said no".
        local saved = { hanoi = true }
        assert.is_true(Games.isEnabled("sudoku", saved, DEFAULTS))
        assert.is_false(Games.isEnabled("sokoban", saved, DEFAULTS))
    end)

    it("treats an empty saved map as no choice made", function()
        assert.is_true(Games.isEnabled("sudoku", {}, DEFAULTS))
    end)
end)

describe("Games.toggled", function()
    local Games
    local DEFAULTS = { sudoku = true }
    local GAMES = { { id = "sudoku" }, { id = "hanoi" }, { id = "sokoban" } }

    setup(function()
        Games = require("games")
    end)

    it("flips the game asked for and leaves the others alone", function()
        local out = Games.toggled(GAMES, "hanoi", nil, DEFAULTS)
        assert.is_true(out.hanoi)
        assert.is_true(out.sudoku)
        assert.is_false(out.sokoban)
    end)

    it("turns a default-on game off", function()
        local out = Games.toggled(GAMES, "sudoku", nil, DEFAULTS)
        assert.is_false(out.sudoku)
    end)

    it("writes an explicit entry for every known game", function()
        -- Otherwise a later change to DEFAULT_ENABLED would move a game the
        -- player had already decided about.
        local out = Games.toggled(GAMES, "hanoi", nil, DEFAULTS)
        for _, g in ipairs(GAMES) do
            assert.are.equal("boolean", type(out[g.id]), g.id .. " left implicit")
        end
    end)

    it("round-trips: toggling twice returns to the starting state", function()
        local once  = Games.toggled(GAMES, "sudoku", nil, DEFAULTS)
        local twice = Games.toggled(GAMES, "sudoku", once, DEFAULTS)
        for _, g in ipairs(GAMES) do
            assert.are.equal(Games.isEnabled(g.id, nil, DEFAULTS), twice[g.id],
                g.id .. " did not come back")
        end
    end)

    it("keeps a game the player enabled even when it is not in the defaults", function()
        local saved = { sokoban = true }
        local out = Games.toggled(GAMES, "hanoi", saved, DEFAULTS)
        assert.is_true(out.sokoban)
    end)
end)

describe("Games.sorted", function()
    local Games

    setup(function()
        Games = require("games")
    end)

    it("orders by the label the player reads, not by id", function()
        local out = Games.sorted({
            { id = "zzz", label = "Anagram" },
            { id = "aaa", label = "Sokoban" },
            { id = "mmm", label = "Hanoi" },
        })
        assert.are.equal("Anagram", out[1].label)
        assert.are.equal("Hanoi",   out[2].label)
        assert.are.equal("Sokoban", out[3].label)
    end)
end)
