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
