# Developer Guide

## Purpose and target

Container Ghost Items is a Factorio 2.0 mod for planning the contents of a chest and producing a blueprint whose chest ghost requests those items. The interface takes broad organizational cues from FactoryPlanner, but this project has its own code and UI. The planner state is per player and is stored in the save.

There are no external mod dependencies. The current container choices are the vanilla wooden, iron, and steel chests and the five vanilla logistic chests. The item-with-quality and recipe choosers use Factorio's native `choose-elem-button` GUI element. Item quality is selected in the native item chooser.

## Project layout

- `info.json` declares the mod and its Factorio 2.0 target.
- `data.lua` registers the planner toggle key binding.
- `control.lua` owns persisted state, GUI construction and events, recipe expansion, capacity calculation, and blueprint creation.
- `locale/en/locale.cfg` contains player-facing text.
- `package_mod.py` builds `name_version.zip` and deploys it to the Factorio mods folder (or a caller-provided output folder).

## Packaging for in-game testing

Run `python3 package_mod.py` to build and install the ZIP at `~/Programs/factorio/mods/container-with-ghost-items_0.1.0.zip`. Pass `--output /path/to/mods` to use a different Factorio mods directory. The script reads the mod name and version from `info.json`, includes runtime files and locale files, and atomically replaces the ZIP if it already exists.

Keep interface text in locale files. Keep calculations independent from GUI event handling where practical so capacity and recipe behavior can be reviewed without tracing rendering code.

## Player workflow

Open the planner with the top-bar **Container Planner** button or `Ctrl+Shift+B`. A player can create any number of plan lines, edit their titles, duplicate or delete them, and move them up or down. Each line is an independent plan.

Add an item with its requested count in the item dialog. Left-click an item to edit it, right-click to remove it, and Ctrl-left-click to choose a recipe and expand its ingredients. On an expanded item, Ctrl-left-click changes the recipe and Ctrl-right-click removes that expansion. Recipe expansion is manual at each level. Ingredient items are shown beside their parent, with a separator. Fluids are excluded because a chest cannot request them as item stacks.

Each line has its own multiplier, selected container, and filters. An empty multiplier means 1. Clicking an item-quality pair in the totals toggles that pair out of or back into the generated blueprint. A plan can generate a blueprint only when its included items fit the selected container.

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
  filtered = { [item_name .. NUL .. quality_name] = boolean },
  roots = { item_node, ... }
}

item_node = {
  id = integer,
  item = item prototype name,
  quality = quality prototype name, -- defaults to normal for older saved plans
  amount = positive integer,
  recipe = optional recipe prototype name,
  children = optional { item_node, ... }
}
```

Node IDs are unique within a player's planner state. Duplicating a line must recursively allocate new node IDs. A node's children represent one selected recipe expansion, not additional manually entered roots. Editing the node item or amount invalidates its expansion; changing the recipe replaces its children.

The modal editor may use transient serializable identifiers in player state while open. Rebuild GUI elements from saved primitive data after GUI recreation; never store `LuaGuiElement` references.

## Calculation rules

For a recipe expansion, find the selected item in the recipe's item products. The number of crafts is `ceil(requested output / output amount for that item)`. Scale each item ingredient by that craft count and round item counts up to whole items. Ignore other recipe products. Ignore fluid ingredients. Recipe availability is not gated on force research: the recipe chooser is available for planning regardless of unlock state.

To calculate totals, recursively visit each root and its expanded children. Sum amounts by item name and quality, then apply the line multiplier. Recipe ingredients inherit the quality of the expanded item at every expansion depth. The filter applies to one item-quality pair within that line: filtered counts remain visible in totals but do not count against container capacity and are omitted from the blueprint. Different qualities occupy separate inventory stacks.

Capacity is measured in inventory slots. For each included item-quality pair, required slots are `ceil(total count / item prototype stack_size)`. The sum must not exceed the selected container's chest inventory size.

## Blueprint representation

Construct one blueprint entity with `entity_number = 1`, the selected container prototype name, and position `{0, 0}`. Group counts by item and quality. Split each group into stack-sized chunks, assigning each chunk to the selected entity's chest inventory through `BlueprintEntity.items` / `BlueprintInsertPlan`. Set each insert plan ID's quality to the selected quality. The inventory stack indexes in `ItemInventoryPositions.in_inventory` are zero-based and must not overlap between item-quality pairs.

Reference: [BlueprintEntity](https://lua-api.factorio.com/latest/concepts/BlueprintEntity.html), [BlueprintInsertPlan](https://lua-api.factorio.com/latest/concepts/BlueprintInsertPlan.html), and [InventoryPosition](https://lua-api.factorio.com/latest/concepts/InventoryPosition.html). These links track the latest API; the implementation targets Factorio 2.0 and should be checked against that exact runtime.

Use the selected item prototype's stack size both for slot validation and for splitting requests. Check capacity again when creating the blueprint, even if the GUI button is disabled, because UI state is not validation. Set the blueprint label from the line title. Create the blueprint on a new blueprint item stack, then deliver it to the cursor or an empty main-inventory slot.

## GUI and event conventions

Build the planner in `player.gui.screen` and the access button in `player.gui.top`. Give interactive controls stable names where code reads them directly; pass row, line, and node identifiers through element `tags` for other event dispatch. Re-render from player state after structural changes. Text edits should update saved primitives without unnecessarily rebuilding the text field while the player is typing.

Handle `on_gui_click` for buttons and item icon mouse gestures, `on_gui_text_changed` for title and multiplier fields, and `on_gui_selection_state_changed` for the container selector. Native prototype chooser values are read from `elem_value` when the modal is confirmed. Register each event handler once and dispatch all relevant actions through that handler.

Recipe expansion must have a bounded depth so a cyclic recipe chain cannot create an unbounded GUI tree. The current implementation limit is 12 nested expansions.

## Validation checklist

The workspace does not currently include a Factorio executable or Lua interpreter, so runtime behavior must be checked in a Factorio 2.0 game with this mod enabled. At minimum, verify:

1. Add, edit, remove, expand, change recipe, collapse, duplicate, reorder, and delete plan content.
2. Save and reload a game; confirm lines and nested expansions persist and multiplayer players see separate plans.
3. Confirm ingredient counts for multiple-output recipes, rounded craft counts, repeated item types, and nested expansions.
4. Confirm filters change capacity and blueprint contents; verify exact-capacity and over-capacity cases for each chest size.
5. Inspect the generated blueprint: it should contain one selected chest and correctly counted ghost item requests in non-overlapping inventory slots.
6. Check cursor delivery, inventory fallback, and full cursor plus full inventory feedback.
7. Select each available quality, confirm it is shown in requested and total items, and inspect generated insert-plan qualities. Expand recipes at multiple levels and confirm all ingredients retain their parent item's quality. Confirm equal item counts at different qualities stay separate and filtering one quality leaves the other included.

Also validate that prototype inventory-size lookup and the blueprint insert-plan shape behave in the minimum supported Factorio version, 2.0. Current online API documentation may describe a later 2.x runtime.

## Current implementation status

The initial implementation is in place and this guide is its behavior contract. Static checks have confirmed valid JSON, balanced Lua block delimiters, and complete English localization keys. Factorio itself and a Lua runtime are unavailable in this workspace, so GUI and blueprint behavior remains unvalidated in-game. Run the checklist above against Factorio 2.0 before publishing.
