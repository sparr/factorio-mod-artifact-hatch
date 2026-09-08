--- What hatches has to belong where the artifact is lying.
local world = require("test.ft.world")

local TWO_POLLS = world.POLL_TICKS * 2 + 60

local function surface_of(planet)
    return game.planets[planet].surface or game.planets[planet].create_surface()
end

--- No ground needs generating and no nest needs to be standing: what belongs on a surface
--- is read off the map's generation settings, which a surface has from the moment it
--- exists. That is the point of reading it there.
local function with_nests(planet)
    return surface_of(planet)
end

describe("an artifact on Gleba", function()
    it("hatches a premature wriggler, which is what the game does with a spoiled egg",
        function()
            local surface = with_nests("gleba")
            local arena = world.arena(surface)
            world.scatter(arena, "alien-artifact", 40)
            after_ticks(TWO_POLLS, function()
                local hatched = world.hatched(arena)
                local names = {}
                for name in pairs(hatched) do names[#names + 1] = name end
                table.sort(names)
                print("GLEBA hatched: " .. table.concat(names, ", "))
                assert.is_true(next(hatched) ~= nil,
                    "forty artifacts sat on Gleba without hatching anything")
                for name in pairs(hatched) do
                    assert.is_true(name:find("pentapod") ~= nil,
                        name .. " came out of an artifact lying on Gleba")
                    assert.is_true(name:find("premature") ~= nil,
                        name .. " hatched, and a newly hatched pentapod is premature")
                end
            end)
        end)

    it("never hatches anything of Nauvis", function()
        local surface = with_nests("gleba")
        local arena = world.arena(surface)
        world.scatter(arena, "alien-artifact", 40)
        after_ticks(TWO_POLLS, function()
            for name in pairs(world.hatched(arena)) do
                assert.is_nil(name:find("biter"),
                    name .. " hatched on Gleba, and biters belong to Nauvis")
                assert.is_nil(name:find("spitter"),
                    name .. " hatched on Gleba, and spitters belong to Nauvis")
            end
        end)
    end)
end)

describe("an artifact on Nauvis", function()
    -- ah-tests hangs artifact loot on biters, so Nauvis is where those belong
    it("hatches something of Nauvis", function()
        local surface = with_nests("nauvis")
        local arena = world.arena(surface)
        world.scatter(arena, "alien-artifact", 40)
        after_ticks(TWO_POLLS, function()
            local hatched = world.hatched(arena)
            assert.is_true(next(hatched) ~= nil, "nothing hatched on Nauvis")
            for name in pairs(hatched) do
                assert.is_true(name:find("biter") ~= nil,
                    name .. " hatched out of an artifact that only biters drop")
            end
        end)
    end)
end)

describe("a surface with no enemies of its own", function()
    -- Vulcanus has demolishers, which are neither nests nor worms and drop nothing
    it("hatches nothing, however many artifacts are lying about", function()
        local surface = with_nests("vulcanus")
        local arena = world.arena(surface)
        world.scatter(arena, "alien-artifact", 40)
        after_ticks(TWO_POLLS, function()
            assert.are.equal(0, world.hatch_count(arena),
                "something hatched on Vulcanus, which has no nests to raise it")
            assert.are.equal(40, world.items(arena),
                "the artifacts were disturbed on a surface where nothing can hatch")
        end)
    end)
end)
