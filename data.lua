data:extend({
  {
    type = "custom-input",
    name = "container-ghost-items-toggle",
    key_sequence = "CONTROL + SHIFT + B",
    action = "lua"
  }
})

data.raw["gui-style"].default.green_slot_button = {
  type = "button_style",
  parent = "green_slot"
}
