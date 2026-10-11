local Planner = {}

local function has_chest_inventory(prototype)
  local ok, size = pcall(function() return prototype.get_inventory_size(defines.inventory.chest) end)
  if ok and size and size > 0 then return size end
end

local function player_data(player_index)
  storage.cip_players = storage.cip_players or {}
  local data = storage.cip_players[player_index]
  if not data then
    data = { lines = {}, next_line_id = 1, next_node_id = 1 }
    storage.cip_players[player_index] = data
  end
  data.default_container = data.default_container or "iron-chest"
  data.default_container_quality = data.default_container_quality or "normal"
  return data
end

local function new_line(data)
  local id = data.next_line_id
  data.next_line_id = id + 1
  return {
    id = id,
    title = "New plan",
    multiplier_text = "",
    roots = {},
    filtered = {},
    container = data.default_container or "iron-chest",
    container_quality = data.default_container_quality or "normal"
  }
end

local function add_node_id(data)
  local id = data.next_node_id
  data.next_node_id = id + 1
  return id
end

local function find_line(data, id)
  for index, line in ipairs(data.lines) do
    if line.id == id then return line, index end
  end
  return nil
end

local function find_node(node, id)
  if node.id == id then return node end
  for _, child in ipairs(node.children or {}) do
    local found = find_node(child, id)
    if found then return found end
  end
end

local function walk_node(node, callback)
  callback(node)
  for _, child in ipairs(node.children or {}) do walk_node(child, callback) end
end

local function clone_node(data, node)
  local copy = {
    id = add_node_id(data), item = node.item, quality = node.quality or "normal",
    amount = node.amount, fluid = node.fluid
  }
  if node.recipe then
    copy.recipe = node.recipe
    copy.children = {}
    for _, child in ipairs(node.children or {}) do
      table.insert(copy.children, clone_node(data, child))
    end
  end
  return copy
end

local function container_options()
  local result = {}
  for name, prototype in pairs(prototypes.entity) do
    local inventory_size = has_chest_inventory(prototype)
    if inventory_size then
      table.insert(result, { name = name, label = prototype.localised_name, slots = inventory_size })
    end
  end
  table.sort(result, function(a,b) return a.name < b.name end)
  return result
end

local function get_multiplier(line)
  if line.multiplier_text == nil or line.multiplier_text == "" then return 1 end
  local value = tonumber(line.multiplier_text)
  if value and value > 0 then return value end
  return nil
end

local function totals_for(line)
  local multiplier = get_multiplier(line)
  if not multiplier then return nil, "multiplier" end
  local totals = {}
  local function count(node, excluded)
    if excluded or node.excluded then return end
    if node.children and #node.children > 0 then
      for _, child in ipairs(node.children) do count(child, false) end
    elseif not node.fluid and prototypes.item[node.item] then
      local key = node.item .. "\0" .. (node.quality or "normal")
      totals[key] = (totals[key] or 0) + math.ceil(node.amount * multiplier)
    end
  end
  for _, root in ipairs(line.roots) do count(root, false) end
  return totals
end

local function capacity_for(line, totals)
  local options = container_options()
  local chosen
  for _, option in ipairs(options) do
    if option.name == line.container then chosen = option; break end
  end
  if not chosen then return false, 0, 0, "container" end
  local slots_needed = 0
  for key, amount in pairs(totals) do
    if not line.filtered[key] then
      local name = key:match("^(.-)%z")
      local item = prototypes.item[name]
      local stack_size = item and item.stack_size or 1
      slots_needed = slots_needed + math.ceil(amount / stack_size)
    end
  end
  return slots_needed <= chosen.slots, slots_needed, chosen.slots, nil
end

local function filtered_totals(line)
  local totals = totals_for(line)
  if not totals then return {} end
  local result = {}
  for key, count in pairs(totals) do
    if not line.filtered[key] then result[key] = count end
  end
  return result
end

local function blueprint_state(line)
  local totals = totals_for(line)
  if not totals then return "invalid_multiplier", nil end
  local fits, _, _, capacity_error = capacity_for(line, totals)
  if capacity_error then return "no_container", totals end
  if not fits then return "over_capacity", totals end
  if #line.roots == 0 or next(filtered_totals(line)) == nil then
    return "empty_plan", totals
  end
  return "ready", totals
end

local function sorted_item_names(totals)
  local names = {}
  for key in pairs(totals) do table.insert(names, key) end
  table.sort(names, function(a, b)
    local ai, aq = a:match("^(.-)%z(.*)$")
    local bi, bq = b:match("^(.-)%z(.*)$")
    if ai == bi then return aq < bq end
    return ai < bi
  end)
  return names
end

local function recipe_output_amount(recipe, item_name)
  for _, product in ipairs(recipe.products or {}) do
    if product.name == item_name then
      local amount = product.amount
      if not amount then
        amount = ((product.amount_min or product.amount_max or 1) + (product.amount_max or product.amount_min or 1)) / 2
      end
      return amount * (product.probability or 1)
    end
  end
end

local function recipe_matches(recipe_name, item_name)
  local recipe = prototypes.recipe[recipe_name]
  if not recipe then return false end
  for _, product in ipairs(recipe.products or {}) do
    if product.name == item_name then return true end
  end
  return false
end

local function ingredient_amount(ingredient)
  local amount = ingredient.amount
  if not amount then
    amount = ((ingredient.amount_min or ingredient.amount_max or 1) + (ingredient.amount_max or ingredient.amount_min or 1)) / 2
  end
  return math.ceil(amount * (ingredient.probability or 1))
end

local function make_recipe_children(data, node, recipe_name)
  local recipe = prototypes.recipe[recipe_name]
  local output_amount = recipe and recipe_output_amount(recipe, node.item)
  if not output_amount or output_amount <= 0 then return false end
  local crafts = math.ceil(node.amount / output_amount)
  local old_children = node.children or {}
  local children = {}
  for _, ingredient in ipairs(recipe.ingredients or {}) do
    if ((ingredient.type == nil or ingredient.type == "item") and prototypes.item[ingredient.name]) or (ingredient.type == "fluid" and prototypes.fluid[ingredient.name]) then
      local amount = ingredient_amount(ingredient) * crafts
      if amount > 0 then
        local fluid = ingredient.type == "fluid"
        local child
        for index, previous in ipairs(old_children) do
          if previous.item == ingredient.name and (previous.fluid or false) == fluid then
            child = previous
            table.remove(old_children, index)
            break
          end
        end
        if child then
          child.amount = amount
          child.quality = node.quality or "normal"
          if child.recipe and recipe_matches(child.recipe, child.item) then make_recipe_children(data, child, child.recipe) end
        else
          child = { id = add_node_id(data), item = ingredient.name, quality = node.quality or "normal", amount = amount, fluid = fluid }
        end
        table.insert(children, child)
      end
    end
  end
  node.recipe = recipe_name
  node.children = children
  return true
end

local function create_blueprint(player, line)
  local totals = totals_for(line)
  if not totals then
    return "invalid_multiplier"
  end
  local items = filtered_totals(line)
  if next(items) == nil then
    return "empty_plan"
  end
  local fits, _, _, capacity_error = capacity_for(line, totals)
  if capacity_error then
    return "no_container"
  end
  if not fits then
    return "over_capacity"
  end

  local destination
  local cursor = player.cursor_stack
  if cursor and cursor.valid and not cursor.valid_for_read then
    destination = cursor
  else
    local inventory = player.get_main_inventory()
    if inventory then
      for index = 1, #inventory do
        if inventory[index].valid and not inventory[index].valid_for_read then
          destination = inventory[index]
          break
        end
      end
    end
  end
  if not destination then
    return "inventory_full"
  end
  local set_ok = destination.set_stack({ name = "blueprint" })
  if not set_ok then
    return "inventory_full"
  end

  local options = container_options()
  local chest = line.container
  local slot_count = 0
  for _, option in ipairs(options) do
    if option.name == chest then slot_count = option.slots end
  end
  local slot_index = 0
  local insert_plans = {}
  for _, key in ipairs(sorted_item_names(items)) do
    local name, quality = key:match("^(.-)%z(.*)$")
    local amount = items[key]
    local stack_size = prototypes.item[name].stack_size or 1
    local positions = {}
    while amount > 0 do
      local count = math.min(stack_size, amount)
      table.insert(positions, {
        inventory = defines.inventory.chest,
        stack = slot_index,
        count = count
      })
      slot_index = slot_index + 1
      amount = amount - count
    end
    table.insert(insert_plans, {
      id = { name = name, quality = quality },
      items = { in_inventory = positions }
    })
  end
  if slot_index > slot_count then
    destination.clear()
    return "over_capacity"
  end
  destination.set_blueprint_entities({
    {
      entity_number = 1,
      name = chest,
      quality = line.container_quality or "normal",
      position = { 0, 0 },
      items = insert_plans
    }
  })
  destination.label = line.title or "Container plan"
  return "created"
end

Planner.has_chest_inventory = has_chest_inventory
Planner.player_data = player_data
Planner.new_line = new_line
Planner.add_node_id = add_node_id
Planner.find_line = find_line
Planner.find_node = find_node
Planner.walk_node = walk_node
Planner.clone_node = clone_node
Planner.container_options = container_options
Planner.get_multiplier = get_multiplier
Planner.totals_for = totals_for
Planner.capacity_for = capacity_for
Planner.filtered_totals = filtered_totals
Planner.blueprint_state = blueprint_state
Planner.sorted_item_names = sorted_item_names
Planner.recipe_output_amount = recipe_output_amount
Planner.recipe_matches = recipe_matches
Planner.ingredient_amount = ingredient_amount
Planner.make_recipe_children = make_recipe_children
Planner.create_blueprint = create_blueprint

return Planner
