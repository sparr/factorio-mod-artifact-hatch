--- Somewhere to leave artifacts lying about.
---
--- The mod sweeps every chunk of every surface on a timer, so a fixture cannot simply
--- drop something and look at it: it has to wait for a poll, and it has to be sure that
--- what it finds afterwards is its own and not another fixture's. So each fixture gets its
--- own square, far from the others.
local world = {}

--- The polling delay from config.lua, in ticks. The mod checks one tick in every cycle,
--- so a fixture has to sit through a whole one to be sure of having been swept.
world.POLL_TICKS = 20 * 60

local ORIGIN = 1024
local SPACING = 64
local RADIUS = 12

---A cleared, paved square of the given surface, one per fixture.
---@param surface LuaSurface
---@return {surface: LuaSurface, centre: MapPosition, radius: number}
function world.arena(surface)
    storage.test_arenas = storage.test_arenas or {}
    local taken = storage.test_arenas[surface.name] or 0
    storage.test_arenas[surface.name] = taken + 1
    local centre = { x = ORIGIN + taken * SPACING, y = ORIGIN }

    surface.request_to_generate_chunks(centre, 2)
    surface.force_generate_chunk_requests()
    local area = {
        { centre.x - RADIUS, centre.y - RADIUS },
        { centre.x + RADIUS, centre.y + RADIUS },
    }
    for _, entity in pairs(surface.find_entities(area)) do
        if entity.valid and entity.type ~= "character" then entity.destroy() end
    end
    local tiles = {}
    for x = -RADIUS, RADIUS do
        for y = -RADIUS, RADIUS do
            tiles[#tiles + 1] = {
                name = "refined-concrete", position = { centre.x + x, centre.y + y } }
        end
    end
    surface.set_tiles(tiles)
    return { surface = surface, centre = centre, radius = RADIUS }
end

---Scatter loose items across the arena, spaced out so that one hatching cannot eat them
---all: the mod clears items within a small radius of whatever hatches.
---@param arena table
---@param item string
---@param count number
function world.scatter(arena, item, count)
    for i = 1, count do
        local at = {
            arena.centre.x - 8 + (i % 9) * 2,
            arena.centre.y - 8 + math.floor(i / 9) * 2,
        }
        arena.surface.spill_item_stack{
            position = at, stack = { name = item, count = 1 },
            enable_looted = false, allow_belts = false, force = nil }
    end
end

---How many loose items are in the arena.
---@param arena table
---@return number
function world.items(arena)
    return arena.surface.count_entities_filtered{
        name = "item-on-ground",
        area = { { arena.centre.x - arena.radius, arena.centre.y - arena.radius },
                 { arena.centre.x + arena.radius, arena.centre.y + arena.radius } } }
end

---Everything that has hatched in the arena, by prototype name.
---@param arena table
---@return table<string, number>
function world.hatched(arena)
    local found = {}
    for _, entity in pairs(arena.surface.find_entities_filtered{
        type = { "unit", "unit-spawner", "turret" },
        area = { { arena.centre.x - arena.radius, arena.centre.y - arena.radius },
                 { arena.centre.x + arena.radius, arena.centre.y + arena.radius } },
    }) do
        found[entity.name] = (found[entity.name] or 0) + 1
    end
    return found
end

---How many things have hatched in the arena, of any kind.
---@param arena table
---@return number
function world.hatch_count(arena)
    local total = 0
    for _, n in pairs(world.hatched(arena)) do total = total + n end
    return total
end

---Turn evolution up on a surface, so that more than the smallest enemy can appear.
---@param surface LuaSurface
---@param factor number
function world.evolve(surface, factor)
    game.forces.enemy.set_evolution_factor(factor, surface)
end

return world
