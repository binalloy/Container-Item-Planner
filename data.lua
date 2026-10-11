data:extend({
  {
    type = "custom-input",
    name = "container-item-planner-toggle",
    key_sequence = "CONTROL + SHIFT + B",
    action = "lua"
  },
  {
    type = "shortcut",
    name = "container-item-planner-open",
    order = "b[blueprints]-z[container-item-planner]",
    action = "lua",
    associated_control_input = "container-item-planner-toggle",
    localised_name = { "container-item-planner.open" },
    icons = {
      { icon = "__base__/graphics/icons/blueprint.png", icon_size = 64 },
      { icon = "__base__/graphics/icons/iron-chest.png", icon_size = 64, scale = 0.166 },
    },
    icon_size = 64,
    small_icons = {
      { icon = "__base__/graphics/icons/blueprint.png", icon_size = 64 },
      { icon = "__base__/graphics/icons/iron-chest.png", icon_size = 64, scale = 0.166 },
    },
    small_icon_size = 64
  }
})

data.raw["gui-style"].default.green_slot_button = {
  type = "button_style",
  parent = "green_slot"
}

data.raw["gui-style"].default.cip_green_titlebar_button = {
  type = "button_style",
  parent = "green_button",
  width = 24,
  height = 24,
  natural_width = 24,
  natural_height = 24,
  padding = 0
}

data.raw["gui-style"].default.cip_titlebar_text_button = {
  type = "button_style",
  parent = "frame_button",
  height = 24,
  natural_height = 24,
  left_padding = 8,
  right_padding = 8,
  font = "heading-2",
  default_font_color = { 0.9, 0.9, 0.9 }
}

data.raw["gui-style"].default.cip_card_horizontal_flow = {
  type = "horizontal_flow_style",
  parent = "horizontal_flow",
  vertical_align = "center",
  horizontal_spacing = 8
}

data:extend({
  {
    type = "sprite",
    name = "container-item-planner-move-up-down",
    filename = "__container-item-planner__/graphics/move-up-down.png",
    width = 40,
    height = 56,
    scale = 0.5,
    flags = { "gui-icon" }
  },
  {
    type = "sprite",
    name = "container-item-planner-move-target",
    filename = "__container-item-planner__/graphics/move-target.png",
    width = 40,
    height = 40,
    scale = 0.5,
    flags = { "gui-icon" }
  }
})
