require "config"

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
        local low_e, low_w, w
        -- spawn_points is a list of {evolution_factor,weight} coords to be interpolated between
        for _,spawn_point in pairs(usd.spawn_points) do
          if spawn_point.evolution_factor == evo then
            -- perfect match
            w = spawn_point.weight
            break
          elseif low_e then
            -- we already found the entry below our target
            -- interpolate from there toward this entry, stop at our target
            w = low_w + 
              (spawn_point.weight - low_w) * 
              ( (evo - low_e) / (spawn_point.evolution_factor - low_e) )
            break
          else
            low_e = spawn_point.evolution_factor
            low_w = spawn_point.weight
          end
        end
        if not w then
          w = low_w
        end
        if not evo_spawn[usd.unit] then
          evo_spawn[usd.unit] = w
        else
          evo_spawn[usd.unit] = evo_spawn[usd.unit] + w
        end
      end
    end
  end
  return evo_spawn
end

local function maybe_hatch(entity,loot_name,probability,evo_spawn)
  if math.random() < probability then
    -- list of biters that can spawn right now and can drop this loot, with their spawn weight/probability
    local total_weight = 0
    local can_spawn = {}
    for entity_name,entity_weight in pairs(loot_to_entity[loot_name]) do
      if evo_spawn[entity_name] and evo_spawn[entity_name]>0 then
        can_spawn[entity_name] = evo_spawn[entity_name] * entity_weight
        total_weight = total_weight + evo_spawn[entity_name] * entity_weight
      end
    end
    -- pick one of those biters at random, weighted
    local target = math.random() * total_weight
    local picked
    for name,weight in pairs(can_spawn) do
      if target < weight then
        picked = name
        break
      end
      target = target - weight
    end
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
                local mean = loot.amount
                  or ((loot.amount_min + loot.amount_max) / 2)
                local expected = (loot.independent_probability or 1) * mean
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
