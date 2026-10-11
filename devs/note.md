[x] 1. Refactor to seperate gui codes and logic codes to two lua files.
[x] 2. In receipt selection, if possible, filter out the receipts that item is not a product. If only one receipt remain, don't show the dialog.
[x] 3. Close button of main window is not in the title bar. Use native close button is possible.
[x] 4. Use a edit button(pen icon) to edit line title. Don't use a text box.
[x] 5. Use native icon button if possible, especially for dialog confirm/cancel, item add/delete.
[x] 6. Multiplier text box is too long and break out of the container. 5 digit length should be enough.
[x] 7. Fraction multiplier should be supported.
[x] 8. Container selection only support 3 types of chest. All chests should be supported. The selection drop down should use chest icon to show selection.
[x] 9. Create blueprint button should use a blueprint icon.
[x] 10. Items in the requested section and total section align vertically instead of horizontally.
[x] 11. Use a square green backgroud plus icon button the same size as item icon following the last item as a `Add item` button.
[x] 12. Short-cut tool tips should lies each short-cut in a line with short-cut high light.
[x] 13. Only the root item is editable and removable. But right click on it could make it not counted in total(icon turns to red background).
[x] 14. When an item is edited but only amount is changed, it keeps its expanded children and update the amount accordingly.
[x] 16. when an item is expanded, its amount should not count in the total. Liquid ingredient should be showed after expandsion but not counted in total as some liquid can be made from filled barrel which is countable.
[x] 17. Filtered item in total should show in red background.
[x] 18. When a dialog pops up, main window should be freezed. Open the the dialog near the cursor if possible.
[x] 19. Seperation between sections(bigger) should be different with seperation bewteen item and its expandsion children(smaller).
[x] 20. Alt-click on item opens the corresponding in-game wiki page.

[x] 1. When click other mod like factorio planner, only close the latest opened dialog. Correct behavior should be closing all the dialog or window all the way back and finally to the main window.
[x] 2. Open mod from short-cut bar. need to design an icon?
[x] 3. Remove horizontal divider above buttons in item selection dialog.
[x] 4. Align center the text and button
[x] 5. Improve plan line ui
6. Some receipt can not be selected without error message.
7. Filter only containers with inventory in right category, and insert gosht item to the inventory slot.
[x] 8. After item selection, focus on amount input.
[x] 9. Open dialog in the center or near cursor, not top left corner. Keep dialog position when content update.
10. New feature: When clicking add line button with a blue print in the cursor, set request items in the new line the same as the items in the blueprint.
11. New feature: create ghost item with specify amount in cursor.
[x] 12. What if too much requested items and total items?
[x] 13. Empty total item hint.