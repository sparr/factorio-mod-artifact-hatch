--- Every surface the game has, with artifacts on it.
---
--- 2.0 made evolution a property of a force on a surface, and this mod asks for it per
--- surface now. Space platforms have no enemies and no evolution at all.
local world = require("test.ft.world")

local PLANETS = { "nauvis", "vulcanus", "gleba", "fulgora", "aquilo" }
local TWO_POLLS = world.POLL_TICKS * 2 + 60

local function surface_of(planet)
    return game.planets[planet].surface or game.planets[planet].create_surface()
end

describe("artifacts on each planet", function()
    for _, planet in pairs(PLANETS) do
        it("does not fail on " .. planet, function()
            local arena = world.arena(surface_of(planet))
            world.scatter(arena, "alien-artifact", 20)
            after_ticks(TWO_POLLS, function()
                -- what hatches, or whether anything does, is a question for 2.1.2; all
                -- that is asked here is that a sweep of every surface comes back
                assert.is_true(world.items(arena) <= 20)
            end)
        end)
    end
end)

describe("evolution is asked for per surface", function()
    it("reads a different figure on each planet", function()
        local nauvis, gleba = game.surfaces.nauvis, surface_of("gleba")
        world.evolve(nauvis, 0.75)
        world.evolve(gleba, 0.25)
        assert.are.equal(0.75, game.forces.enemy.get_evolution_factor(nauvis))
        assert.are.equal(0.25, game.forces.enemy.get_evolution_factor(gleba))
        world.evolve(nauvis, 0)
        world.evolve(gleba, 0)
    end)
end)
