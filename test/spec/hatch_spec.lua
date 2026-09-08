local hatch = require("lib.hatch")

--- Interpolation lands a hair off a round number, so anything that comes out of it is
--- compared with a tolerance rather than for equality.
local function close(actual, expected, tolerance)
    return math.abs(actual - expected) < (tolerance or 1e-9)
end

describe("how much of an item a kill yields", function()
    it("takes a flat amount as it stands", function()
        assert.are.equal(9, hatch.expected_drop{ amount = 9 })
    end)

    it("takes the middle of a range", function()
        assert.are.equal(2, hatch.expected_drop{ amount_min = 1, amount_max = 3 })
        assert.are.equal(6, hatch.expected_drop{ amount_min = 2, amount_max = 10 })
    end)

    -- the field is independent_probability now; it was plain probability before 2.0
    it("scales by the chance of dropping at all", function()
        assert.are.equal(4.5, hatch.expected_drop{ amount = 9, independent_probability = 0.5 })
        local ranged = hatch.expected_drop{
            amount_min = 2, amount_max = 10, independent_probability = 0.7 }
        assert.is_true(close(ranged, 4.2), tostring(ranged))
    end)

    it("treats a missing chance as always", function()
        assert.are.equal(9, hatch.expected_drop{ amount = 9 })
    end)

    it("copes with only one end of a range given", function()
        assert.are.equal(3, hatch.expected_drop{ amount_max = 3 })
        assert.are.equal(2, hatch.expected_drop{ amount_min = 2 })
    end)

    it("yields nothing when there is no amount at all", function()
        assert.are.equal(0, hatch.expected_drop{})
        assert.are.equal(0, hatch.expected_drop{ independent_probability = 1 })
    end)
end)

describe("how heavily a spawner favours a unit", function()
    --- The shape vanilla uses: nothing at first, then rising with evolution
    local POINTS = {
        { evolution_factor = 0.0, weight = 100 },
        { evolution_factor = 0.3, weight = 200 },
        { evolution_factor = 0.6, weight = 0 },
    }

    it("takes a point that matches exactly", function()
        assert.are.equal(100, hatch.weight_at(POINTS, 0.0))
        assert.are.equal(200, hatch.weight_at(POINTS, 0.3))
        assert.are.equal(0, hatch.weight_at(POINTS, 0.6))
    end)

    it("draws a straight line between two points", function()
        assert.is_true(close(hatch.weight_at(POINTS, 0.15), 150),
            tostring(hatch.weight_at(POINTS, 0.15)))
        assert.is_true(close(hatch.weight_at(POINTS, 0.45), 100),
            tostring(hatch.weight_at(POINTS, 0.45)))
        -- a quarter of the way from 100 up to 200
        assert.is_true(close(hatch.weight_at(POINTS, 0.075), 125),
            tostring(hatch.weight_at(POINTS, 0.075)))
    end)

    -- there is nothing to interpolate towards past either end
    it("holds at the nearest point outside the range", function()
        assert.are.equal(100, hatch.weight_at(POINTS, -1))
        assert.are.equal(0, hatch.weight_at(POINTS, 1))
    end)

    it("answers nothing for a unit with no points at all", function()
        assert.are.equal(0, hatch.weight_at({}, 0.5))
    end)

    it("does not divide by zero when two points share an evolution", function()
        local doubled = {
            { evolution_factor = 0.2, weight = 10 },
            { evolution_factor = 0.2, weight = 20 },
        }
        local weight = hatch.weight_at(doubled, 0.1)
        assert.is_true(weight == 10 or weight == 20, "got " .. tostring(weight))
    end)
end)

describe("choosing what comes out", function()
    it("picks the only candidate", function()
        assert.are.equal("small-biter", hatch.pick({ ["small-biter"] = 5 }, 0.0))
        assert.are.equal("small-biter", hatch.pick({ ["small-biter"] = 5 }, 0.99))
    end)

    it("splits the range in proportion to the weights", function()
        local weights = { ["a-biter"] = 1, ["b-biter"] = 3 }
        -- a takes the first quarter, b the rest
        assert.are.equal("a-biter", hatch.pick(weights, 0.0))
        assert.are.equal("a-biter", hatch.pick(weights, 0.24))
        assert.are.equal("b-biter", hatch.pick(weights, 0.26))
        assert.are.equal("b-biter", hatch.pick(weights, 0.99))
    end)

    it("never returns a candidate of no weight", function()
        local weights = { ["never"] = 0, ["always"] = 1 }
        for _, roll in pairs{ 0, 0.25, 0.5, 0.75, 0.999 } do
            assert.are.equal("always", hatch.pick(weights, roll))
        end
    end)

    it("answers nothing when nothing can spawn", function()
        assert.is_nil(hatch.pick({}, 0.5))
        assert.is_nil(hatch.pick({ ["none"] = 0 }, 0.5))
    end)

    -- the same roll has to give the same answer every time, whatever order the table
    -- happens to hand its keys over in
    it("is not at the mercy of table order", function()
        local first = hatch.pick({ a = 1, b = 1, c = 1, d = 1 }, 0.6)
        for _ = 1, 20 do
            assert.are.equal(first, hatch.pick({ d = 1, c = 1, b = 1, a = 1 }, 0.6))
        end
    end)

    it("still answers at a roll of exactly one", function()
        assert.is_not_nil(hatch.pick({ a = 1, b = 1 }, 1.0))
    end)
end)

describe("the newborn form of an enemy", function()
    local HAVE = {
        ["small-wriggler-pentapod"] = true,
        ["small-wriggler-pentapod-premature"] = true,
        ["small-biter"] = true,
    }
    local function exists(name) return HAVE[name] == true end

    -- what the game itself puts down when a pentapod egg spoils
    it("is the premature one where the game has one", function()
        assert.are.equal("small-wriggler-pentapod-premature",
            hatch.newborn("small-wriggler-pentapod", exists))
    end)

    it("is the enemy itself where it has no premature form", function()
        assert.are.equal("small-biter", hatch.newborn("small-biter", exists))
    end)
end)

describe("what can come out of an artifact", function()
    --- Nauvis: a biter nest raising biters, and a worm that stands alone
    local function nauvis_about(name)
        if name == "biter-spawner" then
            return "unit-spawner", { "small-biter", "medium-biter" }
        elseif name == "small-worm-turret" then
            return "turret", nil
        elseif name == "small-biter" or name == "medium-biter" then
            return "unit", nil
        end
        return nil, nil
    end
    local NAUVIS = {
        structures = { ["biter-spawner"] = true, ["small-worm-turret"] = true },
        units = { ["small-biter"] = 100, ["medium-biter"] = 50 },
    }

    it("is the nest's own brood, not the nest", function()
        local weights = hatch.candidates({ ["biter-spawner"] = 4 }, nauvis_about, NAUVIS)
        assert.is_nil(weights["biter-spawner"], "a nest should not hatch out of an egg")
        assert.are.equal(400, weights["small-biter"])
        assert.are.equal(200, weights["medium-biter"])
    end)

    it("is the unit itself when a unit dropped it", function()
        local weights = hatch.candidates({ ["small-biter"] = 2 }, nauvis_about, NAUVIS)
        assert.are.equal(200, weights["small-biter"])
    end)

    -- a worm raises nothing, so there is nothing for its artifact to be but another worm
    it("is a worm itself when a worm dropped it", function()
        local weights = hatch.candidates({ ["small-worm-turret"] = 3 }, nauvis_about, NAUVIS)
        assert.are.equal(3, weights["small-worm-turret"])
    end)

    it("adds up when several things drop the same artifact", function()
        local weights = hatch.candidates(
            { ["biter-spawner"] = 1, ["small-biter"] = 1 }, nauvis_about, NAUVIS)
        assert.are.equal(200, weights["small-biter"])
        assert.are.equal(50, weights["medium-biter"])
    end)

    --- Gleba: its own nests, and nothing of Nauvis about it
    local function gleba_about(name)
        if name == "gleba-spawner" then
            return "unit-spawner", { "small-wriggler-pentapod" }
        elseif name == "biter-spawner" then
            return "unit-spawner", { "small-biter" }
        end
        return nil, nil
    end
    local GLEBA = {
        structures = { ["gleba-spawner"] = true },
        units = { ["small-wriggler-pentapod"] = 300 },
    }

    it("leaves out a Nauvis biter when the artifact is lying on Gleba", function()
        local weights = hatch.candidates(
            { ["gleba-spawner"] = 9, ["biter-spawner"] = 9 }, gleba_about, GLEBA)
        assert.is_nil(weights["small-biter"],
            "a Nauvis biter should not come out of an egg on Gleba")
        assert.are.equal(2700, weights["small-wriggler-pentapod"])
    end)

    it("leaves out a worm that does not stand on this surface", function()
        local weights = hatch.candidates(
            { ["small-worm-turret"] = 3 }, nauvis_about,
            { structures = {}, units = {} })
        assert.are.same({}, weights)
    end)

    it("offers nothing at all where nothing belongs", function()
        local barren = { structures = {}, units = {} }
        assert.are.same({}, hatch.candidates({ ["biter-spawner"] = 4 }, nauvis_about, barren))
    end)

    it("skips a source the game does not have", function()
        assert.are.same({},
            hatch.candidates({ ["no-such-thing"] = 4 }, nauvis_about, NAUVIS))
    end)
end)
