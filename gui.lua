local GUI = {
  frame = "cgi_main_frame",
  modal = "cgi_modal_frame"
}

local Planner = require("planner")
local player_data = Planner.player_data
local new_line = Planner.new_line
local add_node_id = Planner.add_node_id
local find_line = Planner.find_line
local find_node = Planner.find_node
local clone_node = Planner.clone_node
local container_options = Planner.container_options
local totals_for = Planner.totals_for
local capacity_for = Planner.capacity_for
local filtered_totals = Planner.filtered_totals
local blueprint_state = Planner.blueprint_state
local sorted_item_names = Planner.sorted_item_names
local recipe_matches = Planner.recipe_matches
local make_recipe_children = Planner.make_recipe_children

local MAX_RECIPE_DEPTH = 12
local BLUEPRINT_STATUS_MESSAGES = {
  ready = "blueprint",
  invalid_multiplier = "invalid-multiplier",
  no_container = "no-container",
  over_capacity = "over-capacity",
  empty_plan = "empty-plan",
  inventory_full = "inventory-full",
  created = "blueprint-created"
}

local function translated(key)
  return { "container-item-planner." .. key }
end

local function selected_prototype_name(value)
  if type(value) == "string" then return value end
  if value then
    local ok, name = pcall(function() return value.name end)
    if ok and type(name) == "string" then return name end
  end
end

local function selected_quality_name(value)
  local name = selected_prototype_name(value)
  return name or "normal"
end

local function quality_from_selection(value)
  if value then
    local ok, quality = pcall(function() return value.quality end)
    if ok and quality then return selected_quality_name(quality) end
  end
  return "normal"
end

local function safe_field(value, key)
  if not value then return nil end
  local ok, result = pcall(function() return value[key] end)
  if ok then return result end
end

local function add(parent, spec)
  return parent.add(spec)
end

local function add_container_selector(parent, name, action, line_id, container, quality)
  local options, names = container_options(), {}
  for _, option in ipairs(options) do names[#names + 1] = option.name end
  if #options == 0 then
    add(parent, { type = "label", caption = translated("no-container") })
    return nil
  end
  local chooser = add(parent, {
    type = "choose-elem-button", name = name,
    elem_type = "entity-with-quality",
    elem_filters = { { filter = "name", name = names } },
    tags = { action = action, line_id = line_id }
  })
  chooser.elem_value = { name = container, quality = quality or "normal" }
  return chooser
end

local function render_total_column(parent, line)
  local totals = totals_for(line) or {}
  local names = sorted_item_names(totals)
  local total_frame = add(parent, {
    type = "flow", name = "cgi_total_" .. line.id, direction = "horizontal",
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
        number = amount, style = line.filtered[key] and "red_slot_button" or "slot_button", enabled = true,
        tooltip = { "", prototypes.item[name].localised_name, " × ", amount,
          "\n", enabled and translated("filter-item") or translated("include-item") },
        tags = { action = "toggle-filter", line_id = line.id, item = name, quality = quality, filtered = not enabled }
      })
    end
  end
  return total_frame
end

local function render_node(parent, line, node, depth, ancestor_excluded)
  local excluded = ancestor_excluded or node.excluded or false
  local row = add(parent, { type = "flow", direction = "horizontal" })
  local tooltip = node.children
    and translated("expanded-help")
    or translated("expand-help")
  local button_style = excluded and "red_slot_button"
    or (node.recipe and "green_slot_button" or "slot_button")
  add(row, {
    type = "sprite-button", name = "cgi_node_" .. node.id,
    sprite = (node.fluid and "fluid/" or "item/") .. node.item, quality = node.quality or "normal", number = node.amount,
    style = button_style,
    tooltip = tooltip,
    tags = { action = "item-node", line_id = line.id, node_id = node.id, depth = depth, fluid = node.fluid or false, excluded = excluded }
  })
  if node.children and #node.children > 0 then
    add(row, { type = "line", direction = "vertical" })
    for _, child in ipairs(node.children) do
      render_node(row, line, child, depth + 1, excluded)
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
    text = line.multiplier_text or "", numeric = true, allow_decimal = true,
    allow_negative = false, tags = { action = "multiplier", line_id = line.id }
  })
  multiplier_panel["cgi_multiplier_" .. line.id].style.width = 90
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
  local container_controls = add(container_panel, {
    type = "flow", name = "cgi_container_controls_" .. line.id, direction = "horizontal"
  })
  add_container_selector(container_controls, "cgi_container_" .. line.id, "container", line.id,
    line.container, line.container_quality)
  local blueprint_status = blueprint_state(line)
  add(container_controls, {
    type = "sprite-button", name = "cgi_blueprint_" .. line.id,
    sprite = "item/blueprint", style = "slot_button",
    enabled = blueprint_status == "ready",
    tooltip = translated(BLUEPRINT_STATUS_MESSAGES[blueprint_status]),
    tags = { action = "blueprint", line_id = line.id }
  })
end

local function render_main(player)
  local gui = player.gui.screen
  if gui[GUI.frame] and gui[GUI.frame].valid then gui[GUI.frame].destroy() end
  local data = player_data(player.index)
  local frame = add(gui, {
    type = "frame", name = GUI.frame, caption = "",
    direction = "vertical", auto_center = true
  })
  frame.style.minimal_width = 1050
  local header = add(frame, {
    type = "flow", direction = "horizontal", style = "frame_header_flow"
  })
  header.drag_target = frame
  add(header, {
    type = "sprite-button", name = "cgi_add_line_button", sprite = "utility/add",
    style = "cgi_green_titlebar_button", tooltip = translated("add-line"),
    tags = { action = "add-line" }
  })
  local left_spacer = add(header, { type = "empty-widget", style = "draggable_space_header" })
  left_spacer.style.height = 24
  left_spacer.style.horizontally_stretchable = true
  left_spacer.ignored_by_interaction = true
  local title = add(header, { type = "label", caption = translated("title"), style = "frame_title" })
  title.ignored_by_interaction = true
  local spacer = add(header, { type = "empty-widget", style = "draggable_space_header" })
  spacer.style.height = 24
  spacer.style.horizontally_stretchable = true
  spacer.style.right_margin = 4
  spacer.ignored_by_interaction = true
  add(header, {
    type = "button", caption = translated("settings"), style = "cgi_titlebar_text_button",
    tooltip = translated("settings"), tags = { action = "settings" }
  })
  add(header, {
    type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
    tooltip = translated("close"), tags = { action = "close" }
  })
  local content = add(frame, {
    type = "frame", name = "cgi_main_content", direction = "vertical", style = "inside_shallow_frame_with_padding"
  })
  local scroll = add(content, {
    type = "scroll-pane", name = "cgi_scroll", direction = "vertical"
  })
  scroll.style.maximal_height = 700
  for _, line in ipairs(data.lines) do render_line(scroll, data, line) end
  if #data.lines == 0 then
    add(scroll, { type = "label", caption = translated("empty-lines") })
  end
  player.opened = frame
end

local function update_line_calculations(player, line)
  local main = player.gui.screen[GUI.frame]
  if not (main and main.valid) then return end
  local content = main["cgi_main_content"]
  local scroll = content and content["cgi_scroll"]
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
  local controls = container_panel and container_panel["cgi_container_controls_" .. line.id]
  local blueprint_button = controls and controls["cgi_blueprint_" .. line.id]
  if blueprint_button then
    local blueprint_status = blueprint_state(line)
    blueprint_button.enabled = blueprint_status == "ready"
    blueprint_button.tooltip = translated(BLUEPRINT_STATUS_MESSAGES[blueprint_status])
  end
end

local function close_modal(player)
  if player.gui.screen[GUI.modal] and player.gui.screen[GUI.modal].valid then
    player.gui.screen[GUI.modal].destroy()
  end
  player_data(player.index).modal = nil
  local main = player.gui.screen[GUI.frame]
  if main and main.valid then main.enabled = true end
end

local function render_modal(player)
  if player.gui.screen[GUI.modal] and player.gui.screen[GUI.modal].valid then
    player.gui.screen[GUI.modal].destroy()
  end
  local data = player_data(player.index)
  local modal = data.modal
  if not modal then return end
  local main = player.gui.screen[GUI.frame]
  if main and main.valid then main.enabled = false end
  local frame = add(player.gui.screen, {
    type = "frame", name = GUI.modal, caption = "",
    direction = "vertical", auto_center = true
  })
  local recipe_content = frame
  local item_content = frame
  local title_key = modal.kind == "recipe" and "recipe-dialog-title"
    or (modal.kind == "settings" and "settings" or "add-item")
  local header = add(frame, {
    type = "flow", direction = "horizontal", style = "frame_header_flow"
  })
  header.drag_target = frame
  local title = add(header, { type = "label", caption = translated(title_key), style = "frame_title" })
  title.ignored_by_interaction = true
  local spacer = add(header, { type = "empty-widget", style = "draggable_space_header" })
  spacer.style.height = 24
  spacer.style.horizontally_stretchable = true
  spacer.style.right_margin = 4
  spacer.ignored_by_interaction = true
  add(header, {
    type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
    tooltip = translated("close"), tags = { action = "modal-cancel" }
  })
  if modal.kind == "recipe" or modal.kind == "settings" then
    local content = add(frame, {
      type = "frame", name = "cgi_dialog_content", direction = "vertical",
      style = "inside_shallow_frame_with_padding"
    })
    if modal.kind == "recipe" then
      add(content, { type = "label", caption = translated("choose-recipe") })
    end
    recipe_content = content
  else
    item_content = add(frame, {
      type = "frame", name = "cgi_item_dialog_content", direction = "vertical",
      style = "inside_shallow_frame_with_padding"
    })
  end
  if modal.kind == "item" then
    local row = add(item_content, {
      type = "flow", name = "cgi_modal_item_row", direction = "horizontal"
    })
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
  elseif modal.kind == "recipe" then
    local normal, recycling = {}, {}
    for _, name in ipairs(modal.options) do
      local recipe = prototypes.recipe[name]
      local categories = recipe and safe_field(recipe, "categories") or nil
      local is_recycling = false
      if categories then
        for _, category in ipairs(categories) do
          if category == "recycling" then is_recycling = true; break end
        end
      elseif recipe and safe_field(recipe, "category") == "recycling" then
        is_recycling = true
      end
      if is_recycling then
        recycling[#recycling + 1] = name
      else
        normal[#normal + 1] = name
      end
    end
    local function add_recipe_group(title, recipes)
      if #recipes == 0 then return end
      add(recipe_content, { type = "label", caption = translated(title) })
      local grid = add(recipe_content, { type = "table", column_count = 6 })
      for _, name in ipairs(recipes) do
        local recipe = prototypes.recipe[name]
        add(grid, {
          type = "sprite-button", sprite = "recipe/" .. name, style = "slot_button",
          tooltip = recipe and recipe.localised_name or name,
          toggled = modal.selected_recipe == name,
          tags = { action = "recipe-choice", recipe = name }
        })
      end
    end
    add_recipe_group("normal-recipes", normal)
    add_recipe_group("recycling-recipes", recycling)
  else
    local row = add(recipe_content, {
      type = "flow", name = "cgi_default_container_row", direction = "horizontal"
    })
    add(row, { type = "label", caption = translated("default-container") })
    add_container_selector(row, "cgi_default_container", "default-container", nil,
      modal.container, modal.quality)
  end
  if modal.kind == "item" or modal.kind == "settings" then
    local buttons = add(frame, {
      type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow"
    })
    buttons.drag_target = frame
    add(buttons, {
      type = "button", caption = translated("cancel"), style = "back_button",
      tags = { action = "modal-cancel" }
    })
    local spacer = add(buttons, { type = "empty-widget", style = "draggable_space" })
    spacer.style.height = 32
    spacer.style.horizontally_stretchable = true
    spacer.drag_target = frame
    add(buttons, {
      type = "button", caption = translated("confirm"), style = "confirm_button",
      tags = { action = "modal-save" }
    })
  end
  player.opened = frame
end

local function set_modal_for_item(player, line_id, node)
  local data = player_data(player.index)
  data.modal = {
    kind = "item", line_id = line_id, node_id = node and node.id,
    item = node and node.item, quality = node and (node.quality or "normal") or "normal", amount = node and node.amount or 1
  }
  render_modal(player)
end

local function redraw_after_change(player)
  render_main(player)
end

local function set_modal_for_recipe(player, line_id, node)
  local data = player_data(player.index)
  local line = find_line(data, line_id)
  if not line then return end
  local options = {}
  for name in pairs(prototypes.recipe) do if recipe_matches(name, node.item) then options[#options + 1] = name end end
  table.sort(options)
  if #options == 0 then player.print(translated("no-matching-recipes")); return end
  if #options == 1 then
    if make_recipe_children(data, node, options[1]) then redraw_after_change(player) end
    return
  end
  data.modal = {
    kind = "recipe", line_id = line_id, node_id = node.id, item = node.item,
    recipe = node.recipe, selected_recipe = nil, options = options
  }
  render_modal(player)
end

local function set_modal_for_settings(player)
  local data = player_data(player.index)
  data.modal = {
    kind = "settings",
    container = data.default_container or "iron-chest",
    quality = data.default_container_quality or "normal"
  }
  render_modal(player)
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
  local data = player_data(player.index)
  local action = tags.action

  if action == "close" then
    if player.gui.screen[GUI.frame] then player.gui.screen[GUI.frame].destroy() end
    close_modal(player)
    player.opened = nil
  elseif action == "add-line" then
    table.insert(data.lines, new_line(data))
    redraw_after_change(player)
  elseif action == "settings" then
    set_modal_for_settings(player)
  elseif action == "copy" or action == "trash" or action == "up" or action == "down" then
    local line, index = find_line(data, tags.line_id)
    if not line or not index then return end
    if action == "trash" then
      table.remove(data.lines, index)
    elseif action == "copy" then
      local copy = new_line(data)
      copy.title = (line.title or "Plan") .. " copy"
      copy.multiplier_text = line.multiplier_text
      copy.container = line.container
      copy.container_quality = line.container_quality or "normal"
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
  elseif action == "recipe-choice" then
    local modal = data.modal
    if modal and modal.kind == "recipe" and event.button == defines.mouse_button_type.left then
      if event.alt then
        local recipe = prototypes.recipe[tags.recipe]
        if recipe then player.open_factoriopedia_gui(recipe) end
      elseif recipe_matches(tags.recipe, modal.item) then
        local line = find_line(data, modal.line_id)
        local node = line and find_node({ children = line.roots }, modal.node_id)
        if node and make_recipe_children(data, node, tags.recipe) then
          close_modal(player)
          redraw_after_change(player)
        end
      end
    end
  elseif action == "modal-cancel" then
    close_modal(player)
    if player.gui.screen[GUI.frame] then player.opened = player.gui.screen[GUI.frame] end
  elseif action == "modal-save" then
    local modal = data.modal
    if not modal then return end
    if modal.kind == "item" then
      local line = find_line(data, modal.line_id)
      if not line then close_modal(player); return end
      local modal_frame = player.gui.screen[GUI.modal]
      local content = modal_frame and modal_frame["cgi_item_dialog_content"]
      local item_row = content and content["cgi_modal_item_row"]
      local item_button = item_row and item_row["cgi_modal_item"]
      local amount_field = item_row and item_row["cgi_modal_amount"]
      local selected = item_button and item_button.elem_value
      local item = selected_prototype_name(selected)
      local amount = amount_field and tonumber(amount_field.text)
      local quality = selected and quality_from_selection(selected)
      if not (item and prototypes.item[item]) then
        player.print(translated("invalid-item-selection"))
        return
      end
      if not (amount and amount > 0 and amount % 1 == 0) then
        player.print(translated("invalid-item"))
        return
      end
      quality = quality or "normal"
      local node
      if modal.node_id then node = find_node({ children = line.roots }, modal.node_id) end
      if node then
        local changed_selection = node.item ~= item or (node.quality or "normal") ~= quality
        node.item, node.quality, node.amount = item, quality, amount
        if changed_selection then
          node.recipe, node.children = nil, nil
        elseif node.recipe then
          make_recipe_children(data, node, node.recipe)
        end
      else
        table.insert(line.roots, { id = add_node_id(data), item = item, quality = quality, amount = amount })
      end
      close_modal(player)
      redraw_after_change(player)
    elseif modal.kind == "settings" then
      local modal_frame = player.gui.screen[GUI.modal]
      local content = modal_frame and modal_frame["cgi_dialog_content"]
      local row = content and content["cgi_default_container_row"]
      local chooser = row and row["cgi_default_container"]
      local selected = chooser and chooser.elem_value
      local selected_name = selected_prototype_name(selected)
      local available = false
      for _, option in ipairs(container_options()) do
        if option.name == selected_name then available = true; break end
      end
      if not available then
        player.print(translated("choose-container"))
        return
      end
      data.default_container = selected_name
      data.default_container_quality = quality_from_selection(selected)
      close_modal(player)
      if player.gui.screen[GUI.frame] and player.gui.screen[GUI.frame].valid then
        player.opened = player.gui.screen[GUI.frame]
      end
    else
      local line = find_line(data, modal.line_id)
      if not line then close_modal(player); return end
      local recipe = modal.selected_recipe
      local node = find_node({ children = line.roots }, modal.node_id)
      if not (recipe and node and recipe_matches(recipe, node.item) and make_recipe_children(data, node, recipe)) then
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
    if event.alt and event.button == defines.mouse_button_type.left then
      local prototype = tags.fluid and prototypes.fluid[node.item] or prototypes.item[node.item]
      if prototype then player.open_factoriopedia_gui(prototype) end
    elseif event.control and event.button == defines.mouse_button_type.right then
      node.recipe, node.children = nil, nil
      redraw_after_change(player)
    elseif event.control then
      if (tags.depth or 0) >= MAX_RECIPE_DEPTH then
        player.print(translated("depth-limit"))
      else
        set_modal_for_recipe(player, tags.line_id, node)
      end
    elseif event.button == defines.mouse_button_type.right then
      if (tags.depth or 0) > 0 then
        node.excluded = not node.excluded
        redraw_after_change(player)
        return
      end
      local function remove_node(siblings, id)
        for index, candidate in ipairs(siblings) do
          if candidate.id == id then table.remove(siblings, index); return true end
          if remove_node(candidate.children or {}, id) then return true end
        end
        return false
      end
      remove_node(line.roots, node.id)
      redraw_after_change(player)
    elseif (tags.depth or 0) > 0 then
      return
    else
      set_modal_for_item(player, tags.line_id, node)
    end
  elseif action == "toggle-filter" then
    local line = find_line(data, tags.line_id)
    if line and event.button == defines.mouse_button_type.left then
      if event.alt then
        local item = prototypes.item[tags.item]
        if item then player.open_factoriopedia_gui(item) end
      else
        local key = tags.item .. "\0" .. (tags.quality or "normal")
        line.filtered[key] = not line.filtered[key]
        redraw_after_change(player)
      end
    end
  elseif action == "blueprint" then
    local line = find_line(data, tags.line_id)
    if line then
      local result = Planner.create_blueprint(player, line)
      player.print(translated(BLUEPRINT_STATUS_MESSAGES[result]))
    end
  end
end

local function on_gui_elem_changed(event)
  local element = event.element
  if not (element and element.valid) then return end
  local tags = element.tags or {}
  if tags.action == "container" or tags.action == "default-container" then
    local data = player_data(event.player_index)
    local line = tags.action == "container" and find_line(data, tags.line_id) or nil
    local selected = element.elem_value
    local selected_name = selected_prototype_name(selected)
    local available = false
    for _, option in ipairs(container_options()) do
      if option.name == selected_name then available = true; break end
    end
    if tags.action == "default-container" and available then
      if data.modal and data.modal.kind == "settings" then
        data.modal.container = selected_name
        data.modal.quality = quality_from_selection(selected)
      end
    elseif line and available then
      line.container = selected_name
      line.container_quality = quality_from_selection(selected)
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

local function on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then
    player_data(player.index)
  end
end

local function on_player_joined(event)
  local player = game.get_player(event.player_index)
  if player then player_data(player.index) end
end

local function on_init()
  storage.cgi_players = {}
  for _, player in pairs(game.players) do
    player_data(player.index)
  end
end

local function on_configuration_changed()
  storage.cgi_players = storage.cgi_players or {}
  for _, player in pairs(game.players) do
    player_data(player.index)
  end
end

local function on_gui_closed(event)
  local player = game.get_player(event.player_index)
  if player and event.element and event.element.valid then
    local modal = player.gui.screen[GUI.modal]
    if event.element.name == GUI.modal then
      if not (modal and modal.valid and player.opened == modal) then
        close_modal(player)
        local main = player.gui.screen[GUI.frame]
        if main and main.valid then player.opened = main else player.opened = nil end
      end
    elseif event.element.name == GUI.frame then
      -- The main frame is closed when player.opened switches to the modal.
      -- Modal state is the reliable signal that this is an intentional handoff.
      if not player_data(player.index).modal then
        close_modal(player)
        local main = player.gui.screen[GUI.frame]
        if main and main.valid then main.destroy() end
        player.opened = nil
      end
    end
  end
end

local function on_toggle_input(event)
  local player = game.get_player(event.player_index)
  if player then on_open_button(player) end
end

local function on_lua_shortcut(event)
  if event.prototype_name ~= "container-item-planner-open" then return end
  local player = game.get_player(event.player_index)
  if player then on_open_button(player) end
end

return {
  on_init = on_init,
  on_configuration_changed = on_configuration_changed,
  on_player_created = on_player_created,
  on_player_joined = on_player_joined,
  on_gui_click = on_gui_click,
  on_gui_elem_changed = on_gui_elem_changed,
  on_gui_text_changed = on_gui_text_changed,
  on_gui_closed = on_gui_closed,
  on_toggle_input = on_toggle_input,
  on_lua_shortcut = on_lua_shortcut
}
