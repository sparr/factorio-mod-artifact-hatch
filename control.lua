require "config"

local hatch = require("lib.hatch")

local artifact_polling_delay = math.max(artifact_polling_delay_secs,1)*60

--- Which tick of each cycle the poll lands on, so that not every save checks on the same
--- one. 2.0 made calling math.random while the control file is being read an error, and
--- rightly: it happens once per client and would desync. So the offset is drawn when the
--- game is made and kept with the save.
local function chooseOffset()
  if storage.polling_remainder == nil then
    storage.polling_remainder = math.random(artifact_polling_delay) - 1
  end
end

-- local function debug(...)
--   if game.players[1] then
--     game.players[1].print(...)
--   end
-- end

-- local function pos2s(pos)
--   if pos.x then
--     return pos.x..','..pos.y
--   elseif pos[1] then
--     return pos[1]..','..pos[2]
--   end
--   return ''
-- end

-- thanks to KeyboardHack on irc.freenode.net #factorio for this function
local function find_all_entities(args)
  local entities = {}
  for _,surface in pairs(game.surfaces) do
    for chunk in surface.get_chunks() do
        local top, left = chunk.x * 32, chunk.y * 32
        local bottom, right = top + 32, left + 32
        args.area={{top, left}, {bottom, right}}
        for _, ent in pairs(surface.find_entities_filtered(args)) do
            entities[#entities+1] = ent
        end
    end
  end
  return entities
end

local loot_to_entity

--- What the enemy can spawn on one surface right now, by unit name and weight.
---
--- 2.0 took away game.evolution_factor: evolution belongs to a force on a surface, so
--- this has to be asked and answered per surface rather than once for the whole game. A
--- nest on Gleba and a nest on Nauvis are at different points of their own evolution.
local function spawnable_on(surface)
  local evo_spawn = {}
  local evo = game.forces.enemy.get_evolution_factor(surface)
  for _,entity in pairs(prototypes.entity) do
    if entity.type == "unit-spawner" then
      for _,usd in pairs(entity.result_units) do
        local w = hatch.weight_at(usd.spawn_points, evo)
        evo_spawn[usd.unit] = (evo_spawn[usd.unit] or 0) + w
      end
    end
  end
  return evo_spawn
end

local function maybe_hatch(entity,loot_name,probability,evo_spawn)
  if math.random() < probability then
    -- what could come out of this artifact: everything that drops it, weighted by how
    -- much of it that thing drops and by how likely the thing is at this evolution
    local can_spawn = {}
    for entity_name,entity_weight in pairs(loot_to_entity[loot_name]) do
      if evo_spawn[entity_name] and evo_spawn[entity_name]>0 then
        can_spawn[entity_name] = evo_spawn[entity_name] * entity_weight
      end
    end
    local picked = hatch.pick(can_spawn, math.random())
    if not picked then return end
    -- hatch it!
    if entity.surface.create_entity{
      name=picked,
      position=entity.position,
      force='enemy'
    } then
      -- debug("hatched "..picked.." at "..pos2s(entity.position))
      local area = {
        {entity.position.x-artifact_clearing_radius, entity.position.y-artifact_clearing_radius}, 
        {entity.position.x+artifact_clearing_radius, entity.position.y+artifact_clearing_radius}
      }
      for _, ent in pairs(entity.surface.find_entities_filtered{area=area,name="item-on-ground"}) do
        if ent.valid then ent.destroy() end
      end
    end
  end
end

local function onTick(event)
  -- the offset is kept modulo the delay, so turning the polling delay down in the config
  -- of an existing save cannot leave it pointing at a tick that never comes round
  if event.tick%artifact_polling_delay == storage.polling_remainder%artifact_polling_delay then

    -- initialization code, runs once
    -- make a mapping from each loot item to how likely each entity name is to drop it
    if not loot_to_entity then
      loot_to_entity = {}
      for name,entity in pairs(prototypes.entity) do
        if entity.type == "unit" then
          if entity.loot then
            for _,loot in pairs(entity.loot) do
              -- 2.0 turned a loot entry into an ItemProduct: what was item, probability,
              -- count_min and count_max is now name, independent_probability, and either
              -- a flat amount or an amount_min and amount_max pair.
              if string.find(loot.name, 'alien%-artifact') then
                local expected = hatch.expected_drop(loot)
                if not loot_to_entity[loot.name] then
                  loot_to_entity[loot.name] = {}
                end
                loot_to_entity[loot.name][name] =
                  (loot_to_entity[loot.name][name] or 0) + expected
              end
            end
          end
        end
      end
    end

    -- worked out once per surface per poll, since asking is not cheap
    local spawnable = {}

    for _,entity in pairs(find_all_entities{name="item-on-ground"}) do
      if entity.valid then
        local index = entity.surface.index
        if not spawnable[index] then spawnable[index] = spawnable_on(entity.surface) end
        if loot_to_entity[entity.stack.name] then
          -- direct loot hatches as expected
          maybe_hatch(entity,entity.stack.name,artifact_hatching_chance,spawnable[index])
        elseif loot_to_entity['small-' .. entity.stack.name] then
          -- if nothing drops this loot, see if something drops the small version, and spawn that a bit quicker
          maybe_hatch(entity,'small-' .. entity.stack.name,1-((1-artifact_hatching_chance)^2),spawnable[index])
        end
      end
    end

  end
end

script.on_event(defines.events.on_tick, onTick)

script.on_init(chooseOffset)
script.on_configuration_changed(chooseOffset)

--- ah-tests is never published, so this can never fire on a player's machine -- which
--- matters, because info.json keeps test/ out of the package.
if script.active_mods["factorio-test"] and script.active_mods["ah-tests"] then
  require("__factorio-test__/init")({
    "test.ft.hatching",
    "test.ft.surfaces",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
