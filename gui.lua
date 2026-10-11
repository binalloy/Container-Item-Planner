local GUI = {
  frame = "cip_main_frame",
  modal = "cip_modal_frame"
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
    tooltip = translated("container-selector-tooltip"),
    tags = { action = action, line_id = line_id }
  })
  chooser.elem_value = { name = container, quality = quality or "normal" }
  return chooser
end

local function render_total_contents(total_frame, line)
  local totals = totals_for(line) or {}
  local names = sorted_item_names(totals)
  if #names == 0 then
    local empty_flow = add(total_frame, { type = "flow", direction = "horizontal" })
    empty_flow.style.padding = 12
    empty_flow.style.vertical_align = "center"
    add(empty_flow, { type = "label", caption = translated("empty-total") })
    return
  end
  local total_table = add(total_frame, {
    type = "table", name = "cip_total_" .. line.id, column_count = math.min(20, math.max(#names, 1)),
    style = "filter_slot_table",
    tags = { action = "total-column", line_id = line.id }
  })
  total_table.style.horizontal_spacing = 1
  total_table.style.vertical_spacing = 1
  for _, key in ipairs(names) do
    local name, quality = key:match("^(.-)%z(.*)$")
    local amount = totals[key]
    local enabled = not line.filtered[key]
    add(total_table, {
      type = "sprite-button", sprite = "item/" .. name,
      quality = quality,
      number = amount, style = line.filtered[key] and "red_slot_button" or "slot_button", enabled = true,
      tooltip = { "", prototypes.item[name].localised_name, " × ", amount,
        "\n", enabled and translated("filter-item") or translated("include-item") },
      tags = { action = "toggle-filter", line_id = line.id, item = name, quality = quality, filtered = not enabled }
    })
  end
end

local function render_total_column(parent, line)
  local total_frame = add(parent, {
    type = "frame", name = "cip_total_frame_" .. line.id,
    direction = "horizontal", style = "inside_shallow_frame"
  })
  total_frame.style.top_padding = 2
  total_frame.style.bottom_padding = 3
  total_frame.style.left_padding = 3
  total_frame.style.right_padding = 3
  total_frame.style.minimal_height = 40 + total_frame.style.top_padding + total_frame.style.bottom_padding;
  total_frame.style.vertical_align = "center"
  render_total_contents(total_frame, line)
  return total_frame
end

local function count_descendants(node)
  local count = 0
  for _, child in ipairs(node.children or {}) do
    count = count + 1 + count_descendants(child)
  end
  return count
end

local function render_node(parent, line, node, depth, ancestor_excluded)
  local excluded = ancestor_excluded or node.excluded or false
  local row = add(parent, { type = "flow", direction = "horizontal" })
  row.style.horizontal_spacing = 0
  local tooltip = translated(depth == 0 and "root-node-tooltip" or "ingredient-node-tooltip")
  local button_style = excluded and "red_slot_button"
    or (node.recipe and "green_slot_button" or "slot_button")
  add(row, {
    type = "sprite-button", name = "cip_node_" .. node.id,
    sprite = (node.fluid and "fluid/" or "item/") .. node.item, quality = node.quality or "normal", number = node.amount,
    style = button_style,
    tooltip = tooltip,
    tags = { action = "item-node", line_id = line.id, node_id = node.id, depth = depth, fluid = node.fluid or false, excluded = excluded }
  })
  if node.children and #node.children > 0 then
    local expansion = add(row, { type = "flow", direction = "horizontal" })
    expansion.style.top_margin = 4
    expansion.style.horizontal_spacing = 2
    -- expansion.style.horizontally_squashable = true
    for index, child in ipairs(node.children) do
      local ingredient = add(expansion, { type = "flow", direction = "vertical" })
      -- ingredient.style.horizontal_align = "center"
      ingredient.style.vertical_spacing = 0
      -- ingredient.style.maximal_width = 40
      local horizontal = add(ingredient, { type = "line", direction = "horizontal" })
      horizontal.style.width = 40 * (count_descendants(child) + 1)
      horizontal.style.horizontally_stretchable = false
      if index == #node.children then horizontal.style.width = 22 end
      local vertical = add(ingredient, { type = "line", direction = "vertical" })
      vertical.style.height = 6
      vertical.style.left_margin = 18
      vertical.style.top_margin = -2
      vertical.style.vertically_stretchable = false
      render_node(ingredient, line, child, depth + 1, excluded)
    end
  end
  return row
end

local function render_line(parent, data, line)
  local card = add(parent, {
    type = "frame", name = "cip_line_" .. line.id,
    direction = "vertical", style = "shallow_frame"
  })
  card.style.top_padding = 6
  card.style.bottom_padding = 6
  card.style.left_padding = 6
  card.style.right_padding = 6
  card.style.left_margin = 3
  card.style.right_margin = 3
  card.style.top_margin = 3
  local header = add(card, {
    type = "flow", name = "cip_line_header_" .. line.id, direction = "horizontal"
  })
  render_total_column(header, line)
  local controls = add(header, {
    type = "flow", name = "cip_container_controls_" .. line.id,
    direction = "horizontal", style = "cip_card_horizontal_flow"
  })

  local multiplier_label = add(controls, { type = "label", caption = translated("multiplier") })
  multiplier_label.style.left_margin = 8
  local multiplier = add(controls, {
    type = "textfield", name = "cip_multiplier_" .. line.id,
    text = line.multiplier_text or "", numeric = true, allow_decimal = true,
    allow_negative = false, tooltip = translated("multiplier-tooltip"),
    tags = { action = "multiplier", line_id = line.id }
  })
  multiplier.style.width = 90

  add_container_selector(controls, "cip_container_" .. line.id, "container", line.id,
    line.container, line.container_quality)
  local blueprint_status = blueprint_state(line)
  add(controls, {
    type = "sprite-button", name = "cip_blueprint_" .. line.id,
    sprite = "item/blueprint", style = "slot_button",
    enabled = blueprint_status == "ready",
    tooltip = translated(BLUEPRINT_STATUS_MESSAGES[blueprint_status]),
    tags = { action = "blueprint", line_id = line.id }
  })
  local title = add(controls, {
    type = "textfield", name = "cip_title_" .. line.id,
    text = line.title or "", icon_selector = true,
    tooltip = translated("plan-title-tooltip"),
    tags = { action = "title", line_id = line.id }
  })
  title.style.width = 130
  local copy = add(controls, {
    type = "sprite-button", sprite = "utility/copy", style = "tool_button",
    tooltip = translated("duplicate"), tags = { action = "copy", line_id = line.id }
  })
  -- copy.style.width, copy.style.height = 28, 28
  local trash = add(controls, {
    type = "sprite-button", sprite = "utility/trash", style = "red_button",
    tooltip = translated("delete"), tags = { action = "trash", line_id = line.id }
  })
  trash.style.width, trash.style.height = 28, 28
  trash.style.padding = 2
  local move_sprite = data.move_line_id and data.move_line_id ~= line.id
    and "container-item-planner-move-target" or "container-item-planner-move-up-down"
  local move = add(controls, {
    type = "sprite-button", sprite = move_sprite, style = "tool_button",
    tooltip = translated(data.move_line_id == line.id and "move-cancel" or (data.move_line_id and "move-target" or "move-plan")),
    tags = { action = "move-line", line_id = line.id }
  })
  move.style.width, move.style.height = 20, 28
  move.style.padding = 0
  move.toggled = data.move_line_id == line.id

  local roots = add(card, {
    type = "scroll-pane",
    horizontal_scroll_policy = "dont-show-but-allow-scrolling",
  })
  roots.style.width = 900
  roots.style.minimal_height = 60
  -- roots.style.maximal_height = 190
  roots.style.top_margin = 8
  local root_flow = add(roots, { type = "flow", direction = "horizontal" })
  root_flow.style.horizontal_spacing = 2
  for _, root in ipairs(line.roots) do render_node(root_flow, line, root, 0) end
  local add_item = add(root_flow, {
    type = "sprite-button", sprite = "utility/add", style = "green_button",
    tooltip = translated("add-item"), tags = { action = "add-item", line_id = line.id }
  })
  add_item.style.width, add_item.style.height = 32, 32
  add_item.style.margin = 4
  add_item.style.padding = 4
end

local function render_main(player)
  local gui = player.gui.screen
  if gui[GUI.frame] and gui[GUI.frame].valid then gui[GUI.frame].destroy() end
  local data = player_data(player.index)
  local frame = add(gui, {
    type = "frame", name = GUI.frame, caption = "",
    direction = "vertical", auto_center = true
  })
  frame.style.minimal_width = 800
  local header = add(frame, {
    type = "flow", direction = "horizontal", style = "frame_header_flow"
  })
  header.drag_target = frame
  add(header, {
    type = "sprite-button", name = "cip_add_line_button", sprite = "utility/add",
    style = "cip_green_titlebar_button", tooltip = translated("add-line"),
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
    type = "button", caption = translated("settings"), style = "cip_titlebar_text_button",
    tooltip = translated("settings"), tags = { action = "settings" }
  })
  add(header, {
    type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
    tooltip = translated("close"), tags = { action = "close" }
  })
  local scroll = add(frame, {
    type = "scroll-pane", name = "cip_scroll", direction = "vertical"
  })
  scroll.vertical_scroll_policy = "always"
  scroll.style.maximal_height = 700
  for index, line in ipairs(data.lines) do
    render_line(scroll, data, line)
    if index == #data.lines then
      scroll["cip_line_" .. line.id].style.bottom_margin = 3
    end
  end
  if #data.lines == 0 then
    local empty_flow = add(scroll, { type = "flow", direction = "vertical" })
    empty_flow.style.horizontally_stretchable = true
    local empty_label = add(empty_flow, { type = "label", caption = translated("empty-lines") })
    empty_label.style.single_line = false
    empty_label.style.margin = 12
  end
  frame.force_auto_center()
  player.opened = frame
end

local function update_line_calculations(player, line)
  local main = player.gui.screen[GUI.frame]
  if not (main and main.valid) then return end
  local scroll = main["cip_scroll"]
  local card = scroll and scroll["cip_line_" .. line.id]
  local header = card and card["cip_line_header_" .. line.id]
  local total_frame = header and header["cip_total_frame_" .. line.id]
  if not total_frame then return end

  total_frame.clear()
  render_total_contents(total_frame, line)

  local controls = card["cip_container_controls_" .. line.id]
  local blueprint_button = controls and controls["cip_blueprint_" .. line.id]
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

local function render_item_dialog(content, modal)
  local row = add(content, {
    type = "flow", name = "cip_modal_item_row", direction = "horizontal",
    style = "cip_card_horizontal_flow"
  })
  add(row, { type = "label", caption = translated("item") })
  local chooser = add(row, {
    type = "choose-elem-button", name = "cip_modal_item", elem_type = "item-with-quality",
    tags = { action = "modal-item" }
  })
  chooser.elem_value = modal.item and { name = modal.item, quality = modal.quality or "normal" } or nil
  add(row, { type = "label", caption = translated("amount") })
  local amount = add(row, {
    type = "textfield", name = "cip_modal_amount", text = tostring(modal.amount or 1),
    numeric = true, allow_decimal = false, allow_negative = false
  })
  amount.style.width = 90
end

local function render_recipe_dialog(content, modal)
  local flow = add(content, { type = "flow", direction = "vertical" })
  flow.style.vertical_spacing = 6
  add(flow, { type = "label", caption = translated("choose-recipe") })

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
    local group = is_recycling and recycling or normal
    group[#group + 1] = name
  end

  local function add_recipe_group(title, recipes)
    if #recipes == 0 then return end
    title_label = add(flow, { type = "label", caption = translated(title) })
    title_label.style.font = "heading-2"
    title_label.style.top_margin = 6
    local grid = add(flow, { type = "table", column_count = 6 })
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
end

local function render_settings_dialog(content, modal)
  local row = add(content, {
    type = "flow", name = "cip_default_container_row", direction = "horizontal",
    style = "cip_card_horizontal_flow"
  })
  add(row, { type = "label", caption = translated("default-container") })
  add_container_selector(row, "cip_default_container", "default-container", nil,
    modal.container, modal.quality)
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
    direction = "vertical"
  })
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
  local content
  if modal.kind == "item" then
    content = add(frame, {
      type = "frame", name = "cip_item_dialog_content", direction = "vertical",
      style = "inside_shallow_frame_with_padding"
    })
    render_item_dialog(content, modal)
  else
    content = add(frame, {
      type = "frame", name = "cip_dialog_content", direction = "vertical",
      style = "inside_shallow_frame_with_padding"
    })
    if modal.kind == "recipe" then
      render_recipe_dialog(content, modal)
    else
      render_settings_dialog(content, modal)
    end
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
  local anchor = modal.anchor
  local resolution = player.display_resolution
  local size = frame.size
  if anchor and resolution and size then
    local x = anchor.x + anchor.width + 8
    local y = anchor.y
    if x + size.width > resolution.width then
      x = anchor.x - size.width - 8
    end
    x = math.max(0, math.min(x, resolution.width - size.width))
    y = math.max(0, math.min(y, resolution.height - size.height))
    frame.location = { x = x, y = y }
  else
    frame.force_auto_center()
  end
  player.opened = frame
end

local function gui_anchor(element, player)
  local location, size = element.location, element.size
  if not location or not size then
    local main = player.gui.screen[GUI.frame]
    if main and main.valid then
      location, size = main.location, main.size
    end
  end
  if not location or not size then return nil end
  return { x = location.x, y = location.y, width = size.width, height = size.height }
end

local function focus_modal_amount(player, select_text)
  local modal = player.gui.screen[GUI.modal]
  local content = modal and modal["cip_item_dialog_content"]
  local row = content and content["cip_modal_item_row"]
  local amount = row and row["cip_modal_amount"]
  if amount then
    amount.focus()
    if select_text then amount.select_all() end
  end
end

local function set_modal_for_item(player, line_id, node, anchor)
  local data = player_data(player.index)
  data.modal = {
    kind = "item", line_id = line_id, node_id = node and node.id,
    item = node and node.item, quality = node and (node.quality or "normal") or "normal", amount = node and node.amount or 1,
    anchor = gui_anchor(anchor, player)
  }
  render_modal(player)
  if node then focus_modal_amount(player, true) end
end

local function redraw_after_change(player)
  render_main(player)
end

local function set_modal_for_recipe(player, line_id, node, anchor)
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
    recipe = node.recipe, selected_recipe = nil, options = options, anchor = gui_anchor(anchor, player)
  }
  render_modal(player)
end

local function set_modal_for_settings(player, anchor)
  local data = player_data(player.index)
  data.modal = {
    kind = "settings",
    container = data.default_container or "iron-chest",
    quality = data.default_container_quality or "normal",
    anchor = gui_anchor(anchor, player)
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

  if data.move_line_id and action ~= "move-line" then
    data.move_line_id = nil
  end

  if action == "close" then
    if player.gui.screen[GUI.frame] then player.gui.screen[GUI.frame].destroy() end
    close_modal(player)
    player.opened = nil
  elseif action == "add-line" then
    table.insert(data.lines, new_line(data))
    redraw_after_change(player)
  elseif action == "settings" then
    set_modal_for_settings(player, element)
  elseif action == "move-line" then
    local line, index = find_line(data, tags.line_id)
    if not line or not index then return end
    if not data.move_line_id then
      data.move_line_id = line.id
    elseif data.move_line_id == line.id then
      data.move_line_id = nil
    else
      local moving, moving_index = find_line(data, data.move_line_id)
      data.move_line_id = nil
      if moving and moving_index then
        table.remove(data.lines, moving_index)
        table.insert(data.lines, math.min(index, #data.lines + 1), moving)
      end
    end
    redraw_after_change(player)
  elseif action == "copy" or action == "trash" then
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
    end
    redraw_after_change(player)
  elseif action == "add-item" then
    set_modal_for_item(player, tags.line_id, nil, element)
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
      local content = modal_frame and modal_frame["cip_item_dialog_content"]
      local item_row = content and content["cip_modal_item_row"]
      local item_button = item_row and item_row["cip_modal_item"]
      local amount_field = item_row and item_row["cip_modal_amount"]
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
      local content = modal_frame and modal_frame["cip_dialog_content"]
      local row = content and content["cip_default_container_row"]
      local chooser = row and row["cip_default_container"]
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
        set_modal_for_recipe(player, tags.line_id, node, element)
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
      set_modal_for_item(player, tags.line_id, node, element)
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
  if tags.action == "modal-item" then
    if element.elem_value then
      local player = game.get_player(event.player_index)
      if player then focus_modal_amount(player, true) end
    end
  elseif tags.action == "container" or tags.action == "default-container" then
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
  storage.cip_players = {}
  for _, player in pairs(game.players) do
    player_data(player.index)
  end
end

local function on_configuration_changed()
  storage.cip_players = storage.cip_players or {}
  for _, player in pairs(game.players) do
    player_data(player.index)
  end
end

local function on_gui_closed(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local data = player_data(player.index)
  data.move_line_id = nil
  local main = player.gui.screen[GUI.frame]
  local modal = player.gui.screen[GUI.modal]
  local closed_main = main and event.element == main
  local closed_modal = modal and event.element == modal

  -- Assigning the modal as player.opened closes the main window as the active
  -- GUI, but the main frame must remain available underneath the modal.
  local handoff = closed_main and data.modal and modal and modal.valid
  if not handoff then
    if closed_modal then
      close_modal(player)
      player.opened = main
    elseif closed_main then
      if modal and modal.valid then modal.destroy() end
      if main and main.valid then main.destroy() end
      data.modal = nil
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
