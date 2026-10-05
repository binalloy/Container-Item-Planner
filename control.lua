local GUI = {
  button = "cgi_open_button",
  frame = "cgi_main_frame",
  modal = "cgi_modal_frame"
}

local MAX_RECIPE_DEPTH = 12
local vanilla_containers = {
  "wooden-chest", "iron-chest", "steel-chest",
  "logistic-chest-active-provider", "logistic-chest-passive-provider",
  "logistic-chest-storage", "logistic-chest-buffer", "logistic-chest-requester"
}

local function player_data(player_index)
  storage.cgi_players = storage.cgi_players or {}
  local data = storage.cgi_players[player_index]
  if not data then
    data = { lines = {}, next_line_id = 1, next_node_id = 1 }
    storage.cgi_players[player_index] = data
  end
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
    container = "wooden-chest"
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

local function translated(key)
  return { "container-ghost-items." .. key }
end

local function add(parent, spec)
  return parent.add(spec)
end

local function clone_node(data, node)
  local copy = { id = add_node_id(data), item = node.item, quality = node.quality or "normal", amount = node.amount }
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
  for _, name in ipairs(vanilla_containers) do
    local prototype = game.entity_prototypes[name]
    if prototype then
      local inventory_size
      local ok, size = pcall(function()
        return prototype.get_inventory_size(defines.inventory.chest)
      end)
      if ok then inventory_size = size end
      if not inventory_size or inventory_size == 0 then
        local fallback_ok, fallback_size = pcall(function()
          return prototype.inventory_size
        end)
        if fallback_ok then inventory_size = fallback_size end
      end
      if inventory_size and inventory_size > 0 then
        table.insert(result, { name = name, label = prototype.localised_name, slots = inventory_size })
      end
    end
  end
  return result
end

local function get_multiplier(line)
  if line.multiplier_text == nil or line.multiplier_text == "" then return 1 end
  local value = tonumber(line.multiplier_text)
  if value and value > 0 and value % 1 == 0 then return value end
  return nil
end

local function totals_for(line)
  local multiplier = get_multiplier(line)
  if not multiplier then return nil, "multiplier" end
  local totals = {}
  for _, root in ipairs(line.roots) do
    walk_node(root, function(node)
      if game.item_prototypes[node.item] then
        local key = node.item .. "\0" .. (node.quality or "normal")
        totals[key] = (totals[key] or 0) + node.amount * multiplier
      end
    end)
  end
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
      local item = game.item_prototypes[name]
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
  if not totals then return false, translated("invalid-multiplier"), nil end
  local fits, _, _, capacity_error = capacity_for(line, totals)
  if capacity_error then return false, translated("no-container"), totals end
  if not fits then return false, translated("over-capacity"), totals end
  if #line.roots == 0 or next(filtered_totals(line)) == nil then
    return false, translated("empty-plan"), totals
  end
  return true, translated("blueprint"), totals
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

local function render_total_column(parent, line)
  local totals = totals_for(line) or {}
  local names = sorted_item_names(totals)
  local total_frame = add(parent, {
    type = "flow", name = "cgi_total_" .. line.id, direction = "vertical",
    tags = { action = "total-column", line_id = line.id }
  })
  if #names == 0 then
    add(total_frame, { type = "label", caption = "—" })
  else
    for _, key in ipairs(names) do
      local name, quality = key:match("^(.-)%z(.*)$")
      local amount = totals[key]
      local enabled = not line.filtered[key]
      add(total_frame, {
        type = "sprite-button", sprite = "item/" .. name,
        quality = quality,
        number = amount, style = "slot_button", enabled = true,
        auto_toggle = true, toggled = line.filtered[key] or false,
        tooltip = { "", game.item_prototypes[name].localised_name, " × ", amount,
          "\n", enabled and translated("filter-item") or translated("include-item") },
        tags = { action = "toggle-filter", line_id = line.id, item = name, quality = quality, filtered = not enabled }
      })
    end
  end
  return total_frame
end

local function render_node(parent, line, node, depth)
  local row = add(parent, { type = "flow", direction = "horizontal" })
  local tooltip = node.children
    and translated("expanded-help")
    or translated("expand-help")
  add(row, {
    type = "sprite-button", name = "cgi_node_" .. node.id,
    sprite = "item/" .. node.item, quality = node.quality or "normal", number = node.amount, style = "slot_button",
    tooltip = tooltip,
    tags = { action = "item-node", line_id = line.id, node_id = node.id, depth = depth }
  })
  if node.children and #node.children > 0 then
    add(row, { type = "line", direction = "vertical" })
    for _, child in ipairs(node.children) do
      render_node(row, line, child, depth + 1)
    end
  end
  return row
end

local function add_action_button(parent, caption, action, line_id, tooltip)
  return add(parent, {
    type = "button", caption = caption,
    tooltip = tooltip or caption,
    tags = { action = action, line_id = line_id }
  })
end

local function render_line(parent, data, line)
  local card = add(parent, {
    type = "frame", name = "cgi_line_" .. line.id,
    direction = "vertical", style = "inside_shallow_frame"
  })
  local header = add(card, { type = "flow", direction = "horizontal" })
  add(header, {
    type = "textfield", name = "cgi_title_" .. line.id,
    text = line.title or "", style = "stretchable_textfield",
    tags = { action = "title", line_id = line.id }
  })
  local spacer = add(header, { type = "empty-widget" })
  spacer.style.horizontally_stretchable = true
  add_action_button(header, translated("duplicate"), "copy", line.id, translated("duplicate"))
  add_action_button(header, translated("delete"), "trash", line.id, translated("delete"))
  add_action_button(header, "↑", "up", line.id, translated("move-up"))
  add_action_button(header, "↓", "down", line.id, translated("move-down"))

  local body = add(card, {
    type = "flow", name = "cgi_body_" .. line.id, direction = "horizontal"
  })
  local items_panel = add(body, { type = "flow", direction = "vertical" })
  items_panel.style.width = 440
  add(items_panel, { type = "label", caption = translated("item-requested") })
  local roots = add(items_panel, {
    type = "scroll-pane", direction = "vertical",
    horizontal_scroll_policy = "auto", vertical_scroll_policy = "auto"
  })
  roots.style.width = 440
  roots.style.maximal_height = 190
  for _, root in ipairs(line.roots) do
    render_node(roots, line, root, 0)
  end
  add(roots, {
    type = "button", caption = translated("add-item"), style = "button",
    tags = { action = "add-item", line_id = line.id }
  })
  add(body, { type = "line", direction = "vertical" })

  local multiplier_panel = add(body, { type = "flow", direction = "vertical" })
  multiplier_panel.style.width = 110
  add(multiplier_panel, { type = "label", caption = translated("multiplier") })
  add(multiplier_panel, {
    type = "textfield", name = "cgi_multiplier_" .. line.id,
    text = line.multiplier_text or "", numeric = true, allow_decimal = false,
    allow_negative = false, tags = { action = "multiplier", line_id = line.id }
  })
  add(body, { type = "line", direction = "vertical" })

  local total_panel = add(body, {
    type = "flow", name = "cgi_total_panel_" .. line.id, direction = "vertical"
  })
  total_panel.style.width = 180
  add(total_panel, { type = "label", caption = translated("total") })
  local totals = totals_for(line)
  if totals then
    render_total_column(total_panel, line)
  else
    add(total_panel, { type = "label", caption = translated("invalid-multiplier") })
  end
  add(body, { type = "line", direction = "vertical" })

  local container_panel = add(body, {
    type = "flow", name = "cgi_container_panel_" .. line.id, direction = "vertical"
  })
  container_panel.style.width = 200
  add(container_panel, { type = "label", caption = translated("container") })
  local options, names, selected = container_options(), {}, 0
  for index, option in ipairs(options) do
    table.insert(names, option.label)
    if option.name == line.container then selected = index end
  end
  if #names > 0 then
    add(container_panel, {
      type = "drop-down", name = "cgi_container_" .. line.id,
      items = names, selected_index = selected,
      tags = { action = "container", line_id = line.id }
    })
  else
    add(container_panel, { type = "label", caption = translated("no-container") })
  end
  local capacity_ok, blueprint_tooltip = blueprint_state(line)
  add(container_panel, {
    type = "button", name = "cgi_blueprint_" .. line.id,
    caption = translated("blueprint"),
    enabled = capacity_ok, tooltip = blueprint_tooltip,
    tags = { action = "blueprint", line_id = line.id }
  })
end

local function render_main(player)
  local gui = player.gui.screen
  if gui[GUI.frame] and gui[GUI.frame].valid then gui[GUI.frame].destroy() end
  local data = player_data(player.index)
  local frame = add(gui, {
    type = "frame", name = GUI.frame, caption = translated("title"),
    direction = "vertical", auto_center = true
  })
  frame.style.minimal_width = 1050
  local header = add(frame, { type = "flow", direction = "horizontal" })
  local spacer = add(header, { type = "empty-widget" })
  spacer.style.horizontally_stretchable = true
  add(header, {
    type = "button", caption = "×",
    tooltip = translated("close"),
    tags = { action = "close" }
  })
  add(frame, { type = "line" })
  local scroll = add(frame, {
    type = "scroll-pane", name = "cgi_scroll", direction = "vertical"
  })
  scroll.style.maximal_height = 700
  for _, line in ipairs(data.lines) do render_line(scroll, data, line) end
  if #data.lines == 0 then
    add(scroll, { type = "label", caption = translated("empty-lines") })
  end
  add(frame, {
    type = "button", caption = translated("add-line"),
    tags = { action = "add-line" }
  })
  player.opened = frame
end

local function update_line_calculations(player, line)
  local main = player.gui.screen[GUI.frame]
  if not (main and main.valid) then return end
  local scroll = main["cgi_scroll"]
  local card = scroll and scroll["cgi_line_" .. line.id]
  local body = card and card["cgi_body_" .. line.id]
  local total_panel = body and body["cgi_total_panel_" .. line.id]
  if not total_panel then return end

  total_panel.clear()
  add(total_panel, { type = "label", caption = translated("total") })
  local totals = totals_for(line)
  if totals then
    render_total_column(total_panel, line)
  else
    add(total_panel, { type = "label", caption = translated("invalid-multiplier") })
  end

  local container_panel = body["cgi_container_panel_" .. line.id]
  local blueprint_button = container_panel and container_panel["cgi_blueprint_" .. line.id]
  if blueprint_button then
    local enabled, tooltip = blueprint_state(line)
    blueprint_button.enabled = enabled
    blueprint_button.tooltip = tooltip
  end
end

local function close_modal(player)
  if player.gui.screen[GUI.modal] and player.gui.screen[GUI.modal].valid then
    player.gui.screen[GUI.modal].destroy()
  end
  player_data(player.index).modal = nil
end

local function render_modal(player)
  if player.gui.screen[GUI.modal] and player.gui.screen[GUI.modal].valid then
    player.gui.screen[GUI.modal].destroy()
  end
  local data = player_data(player.index)
  local modal = data.modal
  if not modal then return end
  local frame = add(player.gui.screen, {
    type = "frame", name = GUI.modal,
    caption = modal.kind == "recipe" and translated("choose-recipe") or translated("add-item"),
    direction = "vertical", auto_center = true
  })
  if modal.kind == "item" then
    local row = add(frame, { type = "flow", direction = "horizontal" })
    add(row, { type = "label", caption = translated("item") })
    local chooser = add(row, {
      type = "choose-elem-button", name = "cgi_modal_item", elem_type = "item-with-quality",
      tags = { action = "modal-item" }
    })
    chooser.elem_value = modal.item and { name = modal.item, quality = modal.quality or "normal" } or nil
    add(row, { type = "label", caption = translated("amount") })
    add(row, {
      type = "textfield", name = "cgi_modal_amount", text = tostring(modal.amount or 1),
      numeric = true, allow_decimal = false, allow_negative = false
    })
  else
    add(frame, { type = "label", caption = translated("no-recipe") })
    add(frame, {
      type = "choose-elem-button", name = "cgi_modal_recipe", elem_type = "recipe",
      recipe = modal.recipe, tags = { action = "modal-recipe" }
    })
  end
  add(frame, { type = "line" })
  local buttons = add(frame, { type = "flow", direction = "horizontal" })
  add(buttons, {
    type = "button", caption = translated("save"),
    tags = { action = "modal-save" }
  })
  add(buttons, {
    type = "button", caption = translated("cancel"),
    tags = { action = "modal-cancel" }
  })
  player.opened = frame
end

local function recipe_output_amount(recipe, item_name)
  for _, product in ipairs(recipe.products or {}) do
    if (product.type == nil or product.type == "item") and product.name == item_name then
      local amount = product.amount
      if not amount then
        amount = ((product.amount_min or product.amount_max or 1) + (product.amount_max or product.amount_min or 1)) / 2
      end
      return amount * (product.probability or 1)
    end
  end
end

local function ingredient_amount(ingredient)
  local amount = ingredient.amount
  if not amount then
    amount = ((ingredient.amount_min or ingredient.amount_max or 1) + (ingredient.amount_max or ingredient.amount_min or 1)) / 2
  end
  return math.ceil(amount * (ingredient.probability or 1))
end

local function make_recipe_children(data, node, recipe_name)
  local recipe = game.recipe_prototypes[recipe_name]
  local output_amount = recipe and recipe_output_amount(recipe, node.item)
  if not output_amount or output_amount <= 0 then return false end
  local crafts = math.ceil(node.amount / output_amount)
  local children = {}
  for _, ingredient in ipairs(recipe.ingredients or {}) do
    if (ingredient.type == nil or ingredient.type == "item") and game.item_prototypes[ingredient.name] then
      local amount = ingredient_amount(ingredient) * crafts
      if amount > 0 then
        table.insert(children, {
          id = add_node_id(data), item = ingredient.name, quality = node.quality or "normal", amount = amount
        })
      end
    end
  end
  node.recipe = recipe_name
  node.children = children
  return true
end

local function set_modal_for_item(player, line_id, node)
  local data = player_data(player.index)
  data.modal = {
    kind = "item", line_id = line_id, node_id = node and node.id,
    item = node and node.item, quality = node and (node.quality or "normal") or "normal", amount = node and node.amount or 1
  }
  render_modal(player)
end

local function set_modal_for_recipe(player, line_id, node)
  local data = player_data(player.index)
  local line = find_line(data, line_id)
  if not line then return end
  data.modal = {
    kind = "recipe", line_id = line_id, node_id = node.id,
    item = node.item, recipe = node.recipe
  }
  render_modal(player)
end

local function create_blueprint(player, line)
  local totals = totals_for(line)
  if not totals then
    player.print(translated("invalid-multiplier"))
    return
  end
  local items = filtered_totals(line)
  if next(items) == nil then
    player.print(translated("empty-plan"))
    return
  end
  local fits, _, _, capacity_error = capacity_for(line, totals)
  if capacity_error then
    player.print(translated("choose-container"))
    return
  end
  if not fits then
    player.print(translated("over-capacity"))
    return
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
    player.print(translated("inventory-full"))
    return
  end
  local set_ok = destination.set_stack({ name = "blueprint" })
  if not set_ok then
    player.print(translated("inventory-full"))
    return
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
    local stack_size = game.item_prototypes[name].stack_size or 1
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
    player.print(translated("over-capacity"))
    return
  end
  destination.set_blueprint_entities({
    {
      entity_number = 1,
      name = chest,
      position = { 0, 0 },
      items = insert_plans
    }
  })
  destination.label = line.title or "Container plan"
  player.print(translated("blueprint-created"))
end

local function redraw_after_change(player)
  render_main(player)
end

local function on_open_button(player)
  if player.gui.screen[GUI.frame] and player.gui.screen[GUI.frame].valid then
    player.gui.screen[GUI.frame].destroy()
    close_modal(player)
    player.opened = nil
  else
    render_main(player)
  end
end

local function on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then return end
  local tags = element.tags or {}
  local player = game.get_player(event.player_index)
  if not player then return end
  if element.name == GUI.button then
    on_open_button(player)
    return
  end
  local data = player_data(player.index)
  local action = tags.action

  if action == "close" then
    if player.gui.screen[GUI.frame] then player.gui.screen[GUI.frame].destroy() end
    close_modal(player)
    player.opened = nil
  elseif action == "add-line" then
    table.insert(data.lines, new_line(data))
    redraw_after_change(player)
  elseif action == "copy" or action == "trash" or action == "up" or action == "down" then
    local line, index = find_line(data, tags.line_id)
    if not line then return end
    if action == "trash" then
      table.remove(data.lines, index)
    elseif action == "copy" then
      local copy = new_line(data)
      copy.title = (line.title or "Plan") .. " copy"
      copy.multiplier_text = line.multiplier_text
      copy.container = line.container
      copy.filtered = {}
      for name, filtered in pairs(line.filtered or {}) do copy.filtered[name] = filtered end
      for _, root in ipairs(line.roots) do table.insert(copy.roots, clone_node(data, root)) end
      table.insert(data.lines, index + 1, copy)
    elseif action == "up" and index > 1 then
      data.lines[index], data.lines[index - 1] = data.lines[index - 1], data.lines[index]
    elseif action == "down" and index < #data.lines then
      data.lines[index], data.lines[index + 1] = data.lines[index + 1], data.lines[index]
    end
    redraw_after_change(player)
  elseif action == "add-item" then
    set_modal_for_item(player, tags.line_id, nil)
  elseif action == "modal-cancel" then
    close_modal(player)
    if player.gui.screen[GUI.frame] then player.opened = player.gui.screen[GUI.frame] end
  elseif action == "modal-save" then
    local modal = data.modal
    if not modal then return end
    local line = find_line(data, modal.line_id)
    if not line then close_modal(player); return end
    if modal.kind == "item" then
      local item_button = player.gui.screen[GUI.modal]["cgi_modal_item"]
      local amount_field = player.gui.screen[GUI.modal]["cgi_modal_amount"]
      local item = item_button and item_button.elem_value
      local amount = amount_field and tonumber(amount_field.text)
      local quality = item and (item.quality or "normal")
      if not (item and item.name and game.item_prototypes[item.name] and type(quality) == "string"
        and amount and amount > 0 and amount % 1 == 0) then
        player.print(translated("invalid-item"))
        return
      end
      local node
      if modal.node_id then node = find_node({ children = line.roots }, modal.node_id) end
      if node then
        node.item, node.quality, node.amount = item.name, quality, amount
        node.recipe, node.children = nil, nil
      else
        table.insert(line.roots, { id = add_node_id(data), item = item.name, quality = quality, amount = amount })
      end
      close_modal(player)
      redraw_after_change(player)
    else
      local recipe_button = player.gui.screen[GUI.modal]["cgi_modal_recipe"]
      local recipe = recipe_button and recipe_button.elem_value
      local node = find_node({ children = line.roots }, modal.node_id)
      if not (recipe and node and make_recipe_children(data, node, recipe)) then
        player.print(translated("invalid-recipe"))
        return
      end
      close_modal(player)
      redraw_after_change(player)
    end
  elseif action == "item-node" then
    local line = find_line(data, tags.line_id)
    if not line then return end
    local node = find_node({ children = line.roots }, tags.node_id)
    if not node then return end
    if event.control and event.button == defines.mouse_button_type.right then
      node.recipe, node.children = nil, nil
      redraw_after_change(player)
    elseif event.control then
      if (tags.depth or 0) >= MAX_RECIPE_DEPTH then
        player.print(translated("depth-limit"))
      else
        set_modal_for_recipe(player, tags.line_id, node)
      end
    elseif event.button == defines.mouse_button_type.right then
      local function remove_node(siblings, id)
        for index, candidate in ipairs(siblings) do
          if candidate.id == id then table.remove(siblings, index); return true end
          if remove_node(candidate.children or {}, id) then return true end
        end
        return false
      end
      remove_node(line.roots, node.id)
      redraw_after_change(player)
    else
      set_modal_for_item(player, tags.line_id, node)
    end
  elseif action == "toggle-filter" then
    local line = find_line(data, tags.line_id)
    if line and event.button == defines.mouse_button_type.left then
      local key = tags.item .. "\0" .. (tags.quality or "normal")
      line.filtered[key] = not line.filtered[key]
      redraw_after_change(player)
    end
  elseif action == "blueprint" then
    local line = find_line(data, tags.line_id)
    if line then create_blueprint(player, line) end
  end
end

local function on_gui_selection_state_changed(event)
  local element = event.element
  if not (element and element.valid) then return end
  local tags = element.tags or {}
  if tags.action == "container" then
    local line = find_line(player_data(event.player_index), tags.line_id)
    local option = container_options()[element.selected_index]
    if line and option then
      line.container = option.name
      render_main(game.get_player(event.player_index))
    end
  end
end

local function on_gui_text_changed(event)
  local element = event.element
  if not (element and element.valid) then return end
  local tags = element.tags or {}
  local data = player_data(event.player_index)
  local line = find_line(data, tags.line_id)
  if not line then return end
  if tags.action == "title" then
    line.title = element.text
  elseif tags.action == "multiplier" then
    line.multiplier_text = element.text
    update_line_calculations(game.get_player(event.player_index), line)
  end
end

local function add_top_button(player)
  local top = player.gui.top
  if top[GUI.button] and top[GUI.button].valid then return end
  add(top, {
    type = "button", name = GUI.button,
    caption = translated("open"),
    tooltip = translated("title")
  })
end

local function on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then
    player_data(player.index)
    add_top_button(player)
  end
end

local function on_player_joined(event)
  local player = game.get_player(event.player_index)
  if player then add_top_button(player) end
end

script.on_init(function()
  storage.cgi_players = {}
  for _, player in pairs(game.players) do
    player_data(player.index)
    add_top_button(player)
  end
end)

script.on_configuration_changed(function()
  storage.cgi_players = storage.cgi_players or {}
  for _, player in pairs(game.players) do
    player_data(player.index)
    add_top_button(player)
  end
end)

script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(defines.events.on_player_joined_game, on_player_joined)
script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_gui_selection_state_changed, on_gui_selection_state_changed)
script.on_event(defines.events.on_gui_text_changed, on_gui_text_changed)
script.on_event("container-ghost-items-toggle", function(event)
  local player = game.get_player(event.player_index)
  if player then on_open_button(player) end
end)
