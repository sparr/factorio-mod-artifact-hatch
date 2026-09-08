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

--- What belongs on one surface: the enemy structures the world places there, and the
--- units those structures raise, weighted by how far along that surface's evolution is.
---
--- Read off the map's own generation settings rather than off the nests standing about,
--- because there need not be any: a player who has cleared the map still has artifacts,
--- and they should still hatch into something of that world. Nauvis places its enemies
--- under the "enemy-base" control and Gleba under "gleba_enemy_base"; a spawner or worm
--- prototype names the control that places it, so the two meet in the middle. Vulcanus,
--- Fulgora and Aquilo name no enemy control at all, and nothing hatches there.
---
--- 2.0 took away game.evolution_factor: evolution belongs to a force on a surface, so a
--- nest on Gleba and a nest on Nauvis are at different points of their own.
---@param surface LuaSurface
---@return {structures: table<string, boolean>, units: table<string, number>}
local function natives_of(surface)
  local controls = surface.map_gen_settings.autoplace_controls or {}
  local structures, units = {}, {}
  local evo = game.forces.enemy.get_evolution_factor(surface)
  for name,proto in pairs(prototypes.entity) do
    -- only the kinds of thing an enemy is; a rock is placed by a control too
    if proto.type == "unit-spawner" or proto.type == "turret" or proto.type == "unit" then
      local spec = proto.autoplace_specification
      if spec and spec.control and controls[spec.control] then
        structures[name] = true
        if proto.type == "unit-spawner" then
          for _,usd in pairs(proto.result_units) do
            units[usd.unit] = (units[usd.unit] or 0) + hatch.weight_at(usd.spawn_points, evo)
          end
        end
      end
    end
  end
  return { structures = structures, units = units }
end

--- The type of a source and, if it raises any, its brood
local function about_source(name)
  local proto = prototypes.entity[name]
  if not proto then return nil, nil end
  if proto.type ~= "unit-spawner" then return proto.type, nil end
  local brood = {}
  for _,usd in pairs(proto.result_units) do brood[#brood + 1] = usd.unit end
  return proto.type, brood
end

local function exists(name) return prototypes.entity[name] ~= nil end

local function maybe_hatch(entity,loot_name,probability,native)
  if math.random() < probability then
    local weights = hatch.candidates(loot_to_entity[loot_name], about_source, native)
    local picked = hatch.pick(weights, math.random())
    if not picked then return end
    -- whatever comes out of an egg is newly hatched, so the premature form of it if the
    -- game has one. This is what vanilla does when a pentapod egg spoils.
    picked = hatch.newborn(picked, exists)
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
    -- make a mapping from each artifact to how much of it each thing drops
    if not loot_to_entity then
      loot_to_entity = {}
      for name,entity in pairs(prototypes.entity) do
        -- Anything at all that drops an artifact counts as a source. Until 2.1.2 this
        -- only looked at units, which meant it saw nothing of AlienSpaceScience, whose
        -- artifacts come off spawners and worms.
        if entity.loot then
          for _,loot in pairs(entity.loot) do
            if string.find(loot.name, 'alien%-artifact') then
              local expected = hatch.expected_drop(loot)
              if expected > 0 then
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

    -- worked out once per surface per poll, since asking the surface is not cheap
    local native = {}

    for _,entity in pairs(find_all_entities{name="item-on-ground"}) do
      if entity.valid then
        local index = entity.surface.index
        if not native[index] then native[index] = natives_of(entity.surface) end
        if loot_to_entity[entity.stack.name] then
          -- direct loot hatches as expected
          maybe_hatch(entity,entity.stack.name,artifact_hatching_chance,native[index])
        elseif loot_to_entity['small-' .. entity.stack.name] then
          -- if nothing drops this loot, see if something drops the small version, and spawn that a bit quicker
          maybe_hatch(entity,'small-' .. entity.stack.name,1-((1-artifact_hatching_chance)^2),native[index])
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
    "test.ft.planets",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
