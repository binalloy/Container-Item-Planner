# Container Item Planner

![Container Item Planner thumbnail](thumbnail.png)

Container Item Planner helps you plan the contents of a storage container and create a blueprint whose container ghost requests those items. It supports compatible containers from Factorio and other installed mods.

## Features

- Create multiple plans, each with its own title, multiplier, container, and item requests.
- Expand requested items into recipe ingredients, including normal and recycling recipes.
- Track item quality, filter item-quality pairs out of the blueprint, and check whether the remaining items fit the selected container.
- Import place items and, optionally, item requests from a blueprint on your cursor or selected from a blueprint book.
- Generate a blueprint with the selected container and item insertion requests.

Recipe expansion is manual at each level. Fluid ingredients can be viewed and expanded, but are not included in item totals or generated blueprints. Generated blueprints contain one container entity.

## Use in game

Open the planner with its shortcut button or press **Ctrl+Shift+B**. Add a plan, choose a container, then add items and their requested amounts. Ctrl-click an item to expand it into ingredients; if multiple recipes produce it, choose one from the recipe picker. Use the totals to review capacity and filter item-quality pairs before creating the blueprint.

You can also hold a blueprint while adding a plan to import its item requests. The planner stores plans per player in the save.

## Requirements

- Factorio **2.1**
- No required dependency mods

## Development and packaging

To build a ZIP for local testing, run from the mod directory:

```sh
python3 devs/package_mod.py
```

By default, the ZIP is written to `~/Programs/factorio/mods`. Set a different destination with:

```sh
python3 devs/package_mod.py --output /path/to/factorio/mods
```

The package filename and versioned folder are generated from `info.json`. The package includes the runtime Lua files, graphics, locale, and available release files.

To regenerate the Mod Portal thumbnail, install Pillow and run:

```sh
python3 devs/make_thumbnail.py
```

The script reads the vanilla Factorio blueprint and iron chest icons from `~/Programs/factorio` by default. Use `--factorio-dir /path/to/factorio` to point it to another game installation.

See [devs/DEVELOPMENT.md](devs/DEVELOPMENT.md) for implementation details and the in-game validation checklist.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
