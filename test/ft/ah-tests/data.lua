--- Stands in for the mods that put alien artifacts back into the game.
---
--- SchallAlienLoot hangs artifact loot on units, spawners and worms; AlienSpaceScience on
--- spawners and worms only. The suite needs loot on a unit, because that is the whole of
--- what the mod looks at as of 2.1.0, and it needs a second item to check that the mod
--- ignores loot that is not an artifact.
local ARTIFACT = "alien-artifact"

data:extend{
  {
    type = "item", name = ARTIFACT,
    icon = "__base__/graphics/icons/steel-chest.png", icon_size = 64,
    subgroup = "raw-material", order = "z[alien-artifact]", stack_size = 50,
  },
  {
    type = "item", name = "ah-tests-trinket",
    icon = "__base__/graphics/icons/wooden-chest.png", icon_size = 64,
    subgroup = "raw-material", order = "z[ah-tests-trinket]", stack_size = 50,
  },
}

--- The field names are the 2.0 ones. AlienSpaceScience still writes the old item,
--- probability, count_min and count_max, which a 2.1 game refuses to load at all.
local function add_loot(prototype, name, chance, low, high)
  if not prototype then return end
  prototype.loot = prototype.loot or {}
  table.insert(prototype.loot, {
    type = "item", name = name, independent_probability = chance,
    amount_min = low, amount_max = high,
  })
end

-- small biters always drop artifacts, so a test does not have to wait on a die roll
add_loot(data.raw.unit["small-biter"], ARTIFACT, 1, 1, 4)
add_loot(data.raw.unit["medium-biter"], ARTIFACT, 1, 2, 6)
-- and something that is not an artifact, which nothing should hatch out of. It hangs on
-- the small biter deliberately: on a spitter it would prove nothing, because no spitter
-- can spawn at zero evolution, so a trinket would fail to hatch whether the mod was
-- filtering for artifacts or not.
add_loot(data.raw.unit["small-biter"], "ah-tests-trinket", 1, 1, 1)
