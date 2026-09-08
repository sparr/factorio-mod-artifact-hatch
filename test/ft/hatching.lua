--- What happens to artifacts left lying on the ground.
local world = require("test.ft.world")

--- Two polls' worth, so a fixture is not at the mercy of which tick of the cycle the save
--- happened to draw. The chance per poll is 5% per artifact, so with plenty of artifacts
--- something hatches almost every time.
local TWO_POLLS = world.POLL_TICKS * 2 + 60

--- Nauvis places its enemies under the "enemy-base" control whether or not any nest is
--- still standing, so a fixture needs nothing but an arena.
local function arena_with_nest()
    return world.arena(game.surfaces.nauvis)
end

describe("artifacts on the ground", function()
    it("hatch into something eventually", function()
        local arena = arena_with_nest()
        world.scatter(arena, "alien-artifact", 40)
        assert.are.equal(40, world.items(arena), "the artifacts were not laid out")
        after_ticks(TWO_POLLS, function()
            assert.is_true(world.hatch_count(arena) > 0,
                "forty artifacts sat through two polls without hatching anything")
        end)
    end)

    it("hatch into something that drops them", function()
        local arena = arena_with_nest()
        world.scatter(arena, "alien-artifact", 40)
        after_ticks(TWO_POLLS, function()
            local hatched = world.hatched(arena)
            assert.is_true(next(hatched) ~= nil, "nothing hatched")
            -- ah-tests hangs artifact loot on the small and medium biter, and evolution
            -- starts at nothing, so only the small one can appear
            for name in pairs(hatched) do
                assert.are.equal("small-biter", name,
                    name .. " hatched, and only a small biter should at zero evolution")
            end
        end)
    end)

    it("are eaten by whatever hatches out of them", function()
        local arena = arena_with_nest()
        world.scatter(arena, "alien-artifact", 40)
        after_ticks(TWO_POLLS, function()
            assert.is_true(world.hatch_count(arena) > 0, "nothing hatched")
            assert.is_true(world.items(arena) < 40,
                "something hatched but no artifacts were taken off the ground")
        end)
    end)
end)

describe("things that are not artifacts", function()
    it("are left where they lie", function()
        local arena = arena_with_nest()
        world.scatter(arena, "ah-tests-trinket", 40)
        after_ticks(TWO_POLLS, function()
            assert.are.equal(0, world.hatch_count(arena),
                "something hatched out of an item that is not an artifact")
            assert.are.equal(40, world.items(arena), "the trinkets were disturbed")
        end)
    end)

    it("include ordinary items", function()
        local arena = arena_with_nest()
        world.scatter(arena, "iron-plate", 40)
        after_ticks(TWO_POLLS, function()
            assert.are.equal(0, world.hatch_count(arena))
            assert.are.equal(40, world.items(arena))
        end)
    end)
end)

describe("evolution decides what comes out", function()
    --- The chance is a config value read at the moment of hatching, so a fixture can turn
    --- it up and see many hatches in one poll instead of a handful.
    local saved
    before_each(function()
        saved = artifact_hatching_chance
        artifact_hatching_chance = 0.9
    end)
    after_each(function()
        artifact_hatching_chance = saved
        world.evolve(game.surfaces.nauvis, 0)
    end)

    -- at nothing evolution the small biter is the only one a nest will raise, so it is
    -- the only thing an artifact can become however many kinds drop artifacts
    it("gives only the smallest at no evolution", function()
        local arena = arena_with_nest()
        world.scatter(arena, "alien-artifact", 40)
        after_ticks(world.POLL_TICKS + 60, function()
            local hatched = world.hatched(arena)
            assert.is_true(next(hatched) ~= nil, "nothing hatched")
            for name in pairs(hatched) do
                assert.are.equal("small-biter", name,
                    name .. " hatched, and only a small biter should at no evolution")
            end
        end)
    end)

    -- and at full evolution it should be a mix of the bigger ones, not one size every
    -- time: the pick is weighted, not decided
    it("gives a mix of the bigger ones at full evolution", function()
        local arena = arena_with_nest()
        world.evolve(arena.surface, 1.0)
        world.scatter(arena, "alien-artifact", 60)
        after_ticks(world.POLL_TICKS + 60, function()
            local hatched = world.hatched(arena)
            local names, total = {}, 0
            for name, n in pairs(hatched) do names[#names + 1] = name; total = total + n end
            table.sort(names)
            print(("HATCHED at full evolution: %s (%d in all)")
                :format(table.concat(names, ", "), total))
            assert.is_true(total > 4, "only " .. total .. " hatched, too few to judge by")
            assert.is_nil(hatched["small-biter"],
                "a small biter cannot be raised at full evolution")
            assert.is_true(#names > 1,
                "every one of " .. total .. " hatched the same way, so the pick is not "
                .. "weighted at all: got " .. table.concat(names, ", "))
        end)
    end)
end)
