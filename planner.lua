local Planner = {}

local function find_general_inventory(prototype)
  local blueprint_check_ok, not_blueprintable = pcall(function()
    return prototype.has_flag("not-blueprintable")
  end)
  if not blueprint_check_ok or not_blueprintable then return end

  local type_ok, entity_type = pcall(function() return prototype.type end)
  if not type_ok then return end

  -- Inventory IDs are shared across Lua object types. Only query the storage
  -- inventory that belongs to a supported placeable storage entity type.
  local inventory_index
  if entity_type == "container" or entity_type == "logistic-container" then
    inventory_index = defines.inventory.chest
  elseif entity_type == "car" then
    inventory_index = defines.inventory.car_trunk
  elseif entity_type == "cargo-wagon" then
    inventory_index = defines.inventory.cargo_wagon
  elseif entity_type == "spider-vehicle" then
    inventory_index = defines.inventory.spider_trunk
  else
    return
  end

  local ok, size = pcall(function() return prototype.get_inventory_size(inventory_index) end)
  if not ok or not size or size <= 0 then return end

  if entity_type == "container" then
    -- Filtered and custom-stack chest inventories do not have interchangeable slots.
    local inventory_type_ok, inventory_type = pcall(function() return prototype.inventory_type end)
    if not inventory_type_ok or (inventory_type ~= "normal" and inventory_type ~= "with_bar"
        and inventory_type ~= "with_weight_limit") then
      return
    end
  end

  return { index = inventory_index, slots = size }
end

local function is_unsorted_item(prototype)
  if not prototype then return true end
  local ok, unsorted = pcall(function()
    local group, subgroup = prototype.group, prototype.subgroup
    return not group or not subgroup or group.name == "other" or subgroup.name == "other"
  end)
  return not ok or unsorted
end

local function has_sorted_place_item(prototype)
  local ok, place_items = pcall(function() return prototype.items_to_place_this end)
  if not ok or not place_items then return false end
  for _, place_item in ipairs(place_items) do
    local item = prototypes.item[place_item.name]
    if item and not is_unsorted_item(item) then return true end
  end
  return false
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

local function safe_field(value, key)
  if not value then return nil end
  local ok, result = pcall(function() return value[key] end)
  if ok then return result end
end

local function is_blueprint_sandbox_item(prototype)
  local group = safe_field(safe_field(prototype, "group"), "name")
  local subgroup = safe_field(safe_field(prototype, "subgroup"), "name")
  local function matches(name)
    if type(name) ~= "string" then return false end
    local normalized = name:lower():gsub("[^%w]", "")
    return normalized:find("sandbox", 1, true) ~= nil
      or normalized == "bpsb" or normalized:find("bpsb", 1, true) == 1
  end
  return matches(group) or matches(subgroup)
end

local function is_selectable_item(prototype)
  return prototype ~= nil
    and not is_unsorted_item(prototype)
    and not is_blueprint_sandbox_item(prototype)
    and not safe_field(prototype, "hidden")
    and not safe_field(prototype, "parameter")
end

local function add_blueprint_contents_to_line(player, line, data)
  local cursor = player.cursor_stack
  local is_blueprint = safe_field(cursor, "is_blueprint")
  if not cursor or not safe_field(cursor, "valid_for_read") or not is_blueprint then return nil end

  local ok, entities = pcall(function() return cursor.get_blueprint_entities() end)
  if not ok or type(entities) ~= "table" then
    log("[Container Item Planner] Could not read entities from held blueprint: " .. tostring(entities))
    return 0
  end

  local totals = {}
  local function add_total(item_name, quality, amount)
    local item_prototype = prototypes.item[item_name]
    if not is_selectable_item(item_prototype) or type(amount) ~= "number" or amount <= 0 then return end
    quality = quality or "normal"
    local key = item_name .. "\0" .. quality
    totals[key] = (totals[key] or 0) + amount
  end

  for _, entity in ipairs(entities) do
    local imported_requests = false
    for _, request in ipairs(entity.items or {}) do
      local id = request.id or {}
      local positions = request.items or {}
      local amount = tonumber(positions.grid_count) or 0
      for _, position in ipairs(positions.in_inventory or {}) do
        amount = amount + (tonumber(position.count) or 1)
      end
      if amount > 0 then
        add_total(id.name, id.quality, amount)
        imported_requests = true
      end
    end

    -- Import place items for entities without their own explicit item requests.
    if not imported_requests then
      local entity_prototype = prototypes.entity[entity.name]
      local place_items = entity_prototype and safe_field(entity_prototype, "items_to_place_this")
      local place_item = place_items and place_items[1]
      if place_item then
        add_total(place_item.name, entity.quality, place_item.count or 1)
      end
    end
  end

  local keys = {}
  for key in pairs(totals) do keys[#keys + 1] = key end
  table.sort(keys)
  local count = 0
  for _, key in ipairs(keys) do
    local amount = totals[key]
    local item_name, quality = key:match("^(.-)%z(.*)$")
    line.roots[#line.roots + 1] = {
      id = add_node_id(data), item = item_name, quality = quality, amount = amount
    }
    count = count + amount
  end
  if count == 0 then
    log("[Container Item Planner] Held blueprint contains no selectable item requests or placeable entities.")
  else
    log("[Container Item Planner] Imported " .. tostring(count) .. " items from held blueprint.")
  end
  return count
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
    local inventory = find_general_inventory(prototype)
    if inventory and has_sorted_place_item(prototype) then
      table.insert(result, {
        name = name,
        label = prototype.localised_name,
        inventory = inventory.index,
        slots = inventory.slots
      })
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
  if not recipe then return end
  local total = 0
  for _, product in ipairs(recipe.products or {}) do
    if product.name == item_name then
      local amount = product.amount
      if type(amount) ~= "number" or amount <= 0 then
        local minimum = product.amount_min or product.amount_max
        local maximum = product.amount_max or product.amount_min
        amount = minimum and ((minimum + maximum) / 2) or 0
      end
      -- Factorio 2.1 uses independent_probability; probability is retained for older data.
      -- extra_count_fraction is a chance to receive one additional item.
      local probability = product.independent_probability or product.probability or 1
      total = total + (amount + (product.extra_count_fraction or 0)) * probability
    end
  end
  if total > 0 then return total end
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
    local include_item = (ingredient.type == nil or ingredient.type == "item")
      and prototypes.item[ingredient.name]
    local include_fluid = ingredient.type == "fluid" and prototypes.fluid[ingredient.name]
    if include_item or include_fluid then
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
  local chosen
  for _, option in ipairs(options) do
    if option.name == chest then chosen = option; break end
  end
  if not chosen then destination.clear(); return "no_container" end
  local slot_count = chosen.slots
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
        inventory = chosen.inventory,
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
  local blueprint_ok = pcall(function() destination.set_blueprint_entities({
    {
      entity_number = 1,
      name = chest,
      quality = line.container_quality or "normal",
      position = { 0, 0 },
      items = insert_plans
    }
  }) end)
  if not blueprint_ok then
    destination.clear()
    return "invalid_container"
  end
  destination.label = line.title or "Container plan"
  return "created"
end

Planner.find_general_inventory = find_general_inventory
Planner.player_data = player_data
Planner.new_line = new_line
Planner.add_node_id = add_node_id
Planner.add_blueprint_contents_to_line = add_blueprint_contents_to_line
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
