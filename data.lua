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

data.raw["gui-style"].default.cgi_green_titlebar_button = {
  type = "button_style",
  parent = "green_button",
  width = 24,
  height = 24,
  natural_width = 24,
  natural_height = 24,
  padding = 0
}

data.raw["gui-style"].default.cgi_titlebar_text_button = {
  type = "button_style",
  parent = "frame_button",
  height = 24,
  natural_height = 24,
  left_padding = 8,
  right_padding = 8,
  font = "heading-2",
  default_font_color = { 0.9, 0.9, 0.9 }
}
