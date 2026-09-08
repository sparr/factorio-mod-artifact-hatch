--- The arithmetic behind hatching, with no game in it.
---
--- Three decisions have to be made every time an artifact might hatch: how much of an
--- item a thing drops on average, how likely each kind of enemy is at the current
--- evolution, and which one of them to pick. None of that needs a surface or a prototype,
--- so it lives here where it can be checked against plain numbers.
local hatch = {}

---How much of an item one kill yields on average.
---
---2.0 turned a loot entry into an ItemProduct, which gives either a flat `amount` or an
---`amount_min` and `amount_max` pair, and calls the chance `independent_probability`. A
---missing probability means it always drops.
---@param loot {amount: number?, amount_min: number?, amount_max: number?, independent_probability: number?}
---@return number
function hatch.expected_drop(loot)
  local mean = loot.amount
  if not mean then
    local low, high = loot.amount_min, loot.amount_max
    if not low and not high then return 0 end
    mean = ((low or high) + (high or low)) / 2
  end
  local chance = loot.independent_probability
  if chance == nil then chance = 1 end
  return chance * mean
end

---How heavily a spawner favours one unit at a given evolution.
---
---spawn_points is a list of {evolution_factor, weight} in ascending order, and the weight
---between two of them is the straight line from one to the other. Below the first point
---and above the last the nearest one is used, since there is nothing to interpolate
---towards.
---@param spawn_points {evolution_factor: number, weight: number}[]
---@param evolution number
---@return number
function hatch.weight_at(spawn_points, evolution)
  local previous
  for _, point in pairs(spawn_points) do
    if point.evolution_factor == evolution then
      return point.weight
    elseif point.evolution_factor > evolution then
      if not previous then
        -- evolution has not reached the first point yet
        return point.weight
      end
      local span = point.evolution_factor - previous.evolution_factor
      if span == 0 then return point.weight end
      return previous.weight
        + (point.weight - previous.weight)
        * ((evolution - previous.evolution_factor) / span)
    end
    previous = point
  end
  -- past the last point, so it stays where it ended up
  return previous and previous.weight or 0
end

---Choose one name out of a table of name to weight, given a roll between 0 and 1.
---
---The roll is passed in rather than drawn here, so a test can say which one it wants and
---the game can hand over math.random(). Names are taken in a fixed order so that the same
---roll always picks the same one, whatever order the table happens to iterate in.
---@param weights table<string, number>
---@param roll number between 0 and 1
---@return string?
function hatch.pick(weights, roll)
  local names, total = {}, 0
  for name, weight in pairs(weights) do
    if weight and weight > 0 then
      names[#names + 1] = name
      total = total + weight
    end
  end
  if total <= 0 then return nil end
  table.sort(names)
  local target = roll * total
  for _, name in pairs(names) do
    if target < weights[name] then return name end
    target = target - weights[name]
  end
  -- a roll of exactly 1, or a whisker under it after the subtractions
  return names[#names]
end

return hatch
