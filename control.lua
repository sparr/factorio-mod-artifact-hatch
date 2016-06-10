require "config"

if not defines then
    require 'defines'
end

local artifact_polling_delay = math.max(artifact_polling_delay_secs,1)*60
local polling_remainder = math.random(artifact_polling_delay)-1

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
        -- debug("checked chunk during initialisation")
    end
  end
  return entities
end

local loot_to_entity

local function maybe_hatch(entity,loot_name,probability)
  if math.random() < probability then
    -- hatch it!
    if entity.surface.create_entity{
      name=loot_to_entity[loot_name].entity,
      position=entity.position,
      force='enemy'
    } then
      -- debug("hatched "..loot_to_entity[loot_name].entity.." at "..pos2s(entity.position))
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
  if event.tick%artifact_polling_delay == polling_remainder then

    -- initialization code, runs once
    if not loot_to_entity then
      loot_to_entity = {}
      -- figure out the weakest enemy that can drop each loot
      -- to be used to hatch loot back into enemies later
      for name,entity in pairs(game.entity_prototypes) do
        -- <400 health is a hack until we get access to evolution spawn factors
        if entity.type == "unit" and entity.max_health < 400 then
          if entity.loot then
            for _,loot in pairs(entity.loot) do
              if string.find(loot.item, 'alien%-artifact') then
                if (not loot_to_entity[loot.item]) or entity.max_health < loot_to_entity[loot.item].max_health then
                  loot_to_entity[loot.item] = {max_health=entity.max_health,entity=name}
                end
              end
            end
          end
        end
      end
    end

    for _,entity in pairs(find_all_entities{name="item-on-ground"}) do
      if entity.valid then
        if loot_to_entity[entity.stack.name] then
          -- direct loot hatches as expected
          maybe_hatch(entity,entity.stack.name,artifact_hatching_chance)
        elseif loot_to_entity['small-' .. entity.stack.name] then
          -- if nothing drops this loot, see if something drops the small version, and spawn that a bit quicker
          maybe_hatch(entity,'small-' .. entity.stack.name,1-((1-artifact_hatching_chance)^2))
        end
      end
    end

  end
end

script.on_event(defines.events.on_tick, onTick)
