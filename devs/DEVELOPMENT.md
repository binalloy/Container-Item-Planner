# Developer Guide

## Purpose and target

Container Ghost Items targets Factorio 2.1 and plans the contents of a chest, then produces a blueprint whose chest ghost requests those items. The interface takes broad organizational cues from FactoryPlanner, but this project has its own code and UI. The planner state is per player and is stored in the save.

There are no external mod dependencies. Container choices are discovered from entity prototypes that expose a non-empty chest inventory, including modded containers. The item-with-quality and container selectors use Factorio's native `choose-elem-button`; the container selector is filtered to those discovered prototypes. Recipes are selected from slot buttons filtered to recipes that directly produce the selected item or fluid, grouped into normal and recycling recipes.

## Project layout

- `info.json` declares the mod and its Factorio 2.1 target.
- `data.lua` registers the planner toggle key binding.
- `control.lua` registers lifecycle and GUI events and delegates them to `gui.lua`.
- `gui.lua` builds the planner interface and handles GUI events. `planner.lua` owns persisted planner state, recipe expansion, totals, capacity calculations, and blueprint creation.
- `locale/en/locale.cfg` contains player-facing text.
- `package_mod.py` builds `name_version.zip` and deploys it to the Factorio mods folder (or a caller-provided output folder).

## Packaging for in-game testing

Run `python3 devs/package_mod.py` from the mod root to build and install the ZIP at `~/Programs/factorio/mods/container-with-ghost-items_0.1.0.zip`. Pass `--output /path/to/mods` to use a different Factorio mods directory. The script reads the mod name and version from the root `info.json`, includes runtime files and locale files under a versioned top-level folder inside the ZIP, and atomically replaces the ZIP if it already exists. Factorio requires a mod folder inside the archive; the zip filename alone is not enough.

Keep interface text in locale files. Keep calculations independent from GUI event handling where practical so capacity and recipe behavior can be reviewed without tracing rendering code.

## Player workflow

Open the planner with the top-bar **Container Planner** button or `Ctrl+Shift+B`. A player can create any number of plan lines, edit their titles, duplicate or delete them, and move them up or down. Each line is an independent plan.

Add an item with its requested count in the item dialog. Left-click a root item to edit it and right-click to remove it. Ctrl-left-click chooses a directly producing recipe and expands its ingredients; a single matching recipe is selected automatically and no match is reported. When several recipes match, choose one from the normal or recycling recipe slot-button group; selecting a recipe applies it and closes the dialog. Expanded item buttons use `green_slot_button`. On any expanded row, Ctrl-left-click changes the recipe and Ctrl-right-click removes that expansion. Recipe expansion is manual at each level. Ingredient rows are read-only: right-click toggles exclusion of the ingredient and its full descendant branch. Excluded rows are shown in red. Fluid ingredients are displayed and can be expanded, but are omitted from item totals and blueprints. Alt-left-click an item, fluid, recipe slot, or total item to open its Factoriopedia entry.

Each line has its own positive decimal multiplier, selected container and container quality, and item filters. The container chooser uses entity quality selection and only lists entities with a usable chest inventory. An empty multiplier means 1. Each counted item contribution is multiplied and rounded up before contributions are aggregated by item and quality. Clicking an item-quality pair in the totals toggles that pair out of or back into the generated blueprint. A plan can generate a blueprint only when its included items fit the selected container.

The generated blueprint contains one container at the origin. Blueprint item requests are attached to that blueprint entity. Deliver the blueprint to an empty cursor stack; if the cursor is occupied, use the first empty slot in the player's main inventory. Report failure if neither destination is available.

## Saved data model

Store mutable planner data in Factorio's persisted `storage` table, indexed by player index. Do not put GUI elements or Lua objects in persisted state.

```text
storage.cgi_players[player_index] = {
  lines = { line, ... },
  next_line_id = integer,
  next_node_id = integer
}

line = {
  id = integer,
  title = string,
  multiplier_text = string, -- empty means 1
  container = entity prototype name,
  container_quality = quality prototype name, -- defaults to normal for older saved plans
  filtered = { [item_name .. NUL .. quality_name] = boolean },
  roots = { item_node, ... }
}

item_node = {
  id = integer,
  item = item prototype name,
  quality = quality prototype name, -- defaults to normal for older saved plans
  amount = positive integer,
  fluid = optional boolean, -- fluid ingredient row; never counted as a chest item
  excluded = optional boolean, -- excludes this node and its descendant branch
  recipe = optional recipe prototype name,
  children = optional { item_node, ... }
}
```

Node IDs are unique within a player's planner state. Duplicating a line must recursively allocate new node IDs. A node's children represent one selected recipe expansion, not additional manually entered roots. Changing an item's selected prototype or quality clears its expansion. Changing only its amount recalculates its selected recipe and descendants while retaining compatible nested expansions. Changing the recipe replaces its children.

The modal editor may use transient serializable identifiers in player state while open. Rebuild GUI elements from saved primitive data after GUI recreation; never store `LuaGuiElement` references.

## Calculation rules

For a recipe expansion, find the selected item or fluid in the recipe's products. The number of crafts is `ceil(requested output / output amount for that product)`. Scale each ingredient by that craft count and round ingredient amounts up to whole units. Keep fluid ingredients visible as fluid rows, but do not include them in item totals. Recipe availability is not gated on force research: all directly producing recipes are available regardless of unlock state.

To calculate totals, recursively visit each root. An expanded node contributes its descendants rather than its own amount; a collapsed node contributes its amount. Excluded nodes suppress their entire branch. For each included item contribution, apply the line multiplier and round up, then aggregate by item name and quality. Recipe ingredient rows inherit the nearest item's quality. The filter applies to one item-quality pair within that line: filtered counts remain visible in totals but do not count against container capacity and are omitted from the blueprint. Different qualities occupy separate inventory stacks.

Capacity is measured in inventory slots. For each included item-quality pair, required slots are `ceil(total count / item prototype stack_size)`. The sum must not exceed the selected container's chest inventory size.

## Blueprint representation

Construct one blueprint entity with `entity_number = 1`, the selected container prototype name and quality, and position `{0, 0}`. Group counts by item and quality. Split each group into stack-sized chunks, assigning each chunk to the selected entity's chest inventory through `BlueprintEntity.items` / `BlueprintInsertPlan`. Set each insert plan ID's quality to the selected item quality. The inventory stack indexes in `ItemInventoryPositions.in_inventory` are zero-based and must not overlap between item-quality pairs.

Reference: [BlueprintEntity](https://lua-api.factorio.com/latest/concepts/BlueprintEntity.html), [BlueprintInsertPlan](https://lua-api.factorio.com/latest/concepts/BlueprintInsertPlan.html), and [InventoryPosition](https://lua-api.factorio.com/latest/concepts/InventoryPosition.html). These links track the latest API; runtime behavior should be checked against the Factorio 2.1 target.

Use the selected item prototype's stack size both for slot validation and for splitting requests. Check capacity again when creating the blueprint, even if the GUI button is disabled, because UI state is not validation. Set the blueprint label from the line title. Create the blueprint on a new blueprint item stack, then deliver it to the cursor or an empty main-inventory slot.

## GUI and event conventions

Build the planner in `player.gui.screen` and the access button in `player.gui.top`. Give interactive controls stable names where code reads them directly; pass row, line, and node identifiers through element `tags` for other event dispatch. Re-render from player state after structural changes. Text edits should update saved primitives without unnecessarily rebuilding the text field while the player is typing.

Use the standard-window pattern for the main planner: a titlebar with a frame title, drag handle, and close action button, followed by a padded content frame. It must close from the close action and Factorio's E close-GUI action. Use the dialog-window pattern for the item editor: a caption, padded content frame, and bottom row with Cancel on the left and Confirm on the right.

Handle `on_gui_click` for buttons, recipe slot buttons, and item icon mouse gestures, `on_gui_text_changed` for title and multiplier fields, `on_gui_elem_changed` for the container selector, and `on_gui_closed` for native frame closure. The native item-with-quality chooser value is read from `elem_value` when the modal is confirmed. The recipe slot buttons contain only directly producing recipe names. Register each event handler once and dispatch all relevant actions through that handler.

Recipe expansion must have a bounded depth so a cyclic recipe chain cannot create an unbounded GUI tree. The current implementation limit is 12 nested expansions.

## Validation checklist

The workspace does not currently include a Factorio executable or Lua interpreter, so runtime behavior must be checked in a Factorio 2.1 game with this mod enabled. At minimum, verify:

1. Add, edit, remove, expand, change recipe, collapse, exclude and restore ingredient branches, duplicate, reorder, and delete plan content. Confirm ingredient rows cannot be edited directly.
2. Save and reload a game; confirm lines and nested expansions persist and multiplayer players see separate plans.
3. Confirm zero, one, and multiple matching recipe cases; ingredient counts for item and fluid products, multiple-output recipes, rounded craft counts, repeated item types, nested expansions, and preservation of nested expansions after amount edits.
4. Confirm filters change capacity and blueprint contents; verify exact-capacity and over-capacity cases for each chest size.
5. Inspect the generated blueprint: it should contain one selected chest and correctly counted ghost item requests in non-overlapping inventory slots.
6. Check cursor delivery, inventory fallback, and full cursor plus full inventory feedback.
7. Select each available quality, confirm it is shown in requested and total items, and inspect generated insert-plan qualities. Expand recipes at multiple levels and confirm item ingredients inherit the nearest item ancestor's quality. Confirm equal item counts at different qualities stay separate and filtering one quality leaves the other included.
8. Verify decimal multipliers round each contribution up before aggregation, and confirm fluid rows stay visible but do not affect totals, capacity, or blueprint requests.
9. Verify all vanilla and modded entities with usable chest inventories are offered, container qualities can be selected and appear on the generated blueprint chest, and Alt-click opens item and fluid Factoriopedia entries.

Also validate that prototype inventory-size lookup and the blueprint insert-plan shape behave in the minimum supported Factorio version, 2.0. Current online API documentation may describe a later 2.x runtime.

## Current implementation status

The implementation includes recipe filtering and auto-selection, fluid ingredient display, descendant-based totals, branch exclusions, decimal multipliers, chest-inventory prototype discovery, native frame close handling, and Factoriopedia links. GUI handling and planner logic are split across `gui.lua` and `planner.lua`, with event registration in `control.lua`. This workspace has no Factorio executable or Lua parser. GUI, save/load, and blueprint behavior must be checked in Factorio 2.1 using the checklist above before publishing.
