# Frequent Issues <!-- omit in toc -->

- [Items are moved to the always-hidden section](#items-are-moved-to-the-always-hidden-section)
- [Ice removed an item](#ice-removed-an-item)
- [Ice does not remember the order of items](#ice-does-not-remember-the-order-of-items)
- [How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?](#how-do-i-solve-the-ice-cannot-arrange-menu-bar-items-in-automatically-hidden-menu-bars-error)

## Items are moved to the always-hidden section

macOS initially adds some new items to the far left of the menu bar, so an item can briefly appear in Ice's always-hidden section. Ice records item
layouts, restores recognized items to their saved sections, and places newly discovered items in the visible section by default.

If an item remains in the wrong section, make sure Ice still has Accessibility permission and temporarily disable the system's automatic menu bar
hiding while arranging items. Then Command + drag the item to the desired section so Ice can record the updated layout.

## Ice removed an item

Ice does not remove another application's menu bar item. Check the hidden and always-hidden sections first, then check whether the owning application
is still running or has disabled its menu bar item. Option + click the Ice icon shows the always-hidden section.

## Ice does not remember the order of items

Ice records the order after a Command + drag or a successful drag in the Menu Bar Layout settings. If it cannot restore an order, confirm that
Accessibility permission is granted and follow the automatic menu bar hiding steps below before arranging the items again.

## How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?

1. Open `System Settings` on your Mac
2. Go to `Control Center`
3. Select `Never` as shown in the image below
4. Update your `Menu Bar Items` in `Ice`
5. Return `Automatically hide and show the menu bar` to your preferred settings

![Disable Menu Bar Hiding](https://github.com/user-attachments/assets/74c1fde6-d310-4fe3-9f2b-703d8ccb636a)
