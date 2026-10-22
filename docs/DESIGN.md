# Design System — TimbreBox

**Language: English · [简体中文](./DESIGN.zh-CN.md)**

## Product Context

- **What this is:** A lightweight, local-first music player for five platforms.
- **Who it's for:** People who want one calm place to search and play music without an account flow.
- **Product type:** Native application with desktop and mobile shells.

## Aesthetic Direction

- **Direction:** Refined liquid glass for a focused listening tool.
- **Decoration level:** Intentional. Warm static gradients, subtle translucent surfaces and one gold accent create depth without permanent blur or animation.
- **Mood:** Quiet, compact and tactile. Content should feel arranged, never crowded.

## Typography

- **Display:** Georgia for restrained editorial headings only.
- **Body and UI:** Flutter platform sans-serif for predictable five-platform rendering and low package cost.
- **Data:** Body face with tabular numeric treatment where available.
- **Scale:** 10/12px metadata, 14px body, 18px section title, 26px page title, 31px display title.

## Color

- **Canvas:** `#10110F`
- **Raised canvas:** `#181914`
- **Ink:** `#F0EEE8`
- **Muted:** `#AAA7A0`
- **Accent:** `#E1B27B`
- **Glass line:** white at 14% opacity
- **Glass surfaces:** white at 7–11% opacity

## Spacing & Layout

- **Base unit:** 4px.
- **Density:** Compact desktop, comfortable touch targets on mobile.
- **Search:** One scrolling search workspace. The persistent global query bar routes into source tabs; only the selected source's results are rendered. The page must never duplicate the global input or combine unrelated source rows into a single undifferentiated feed.
- **Desktop baseline:** 974 × 614 pt content window, with no homepage vertical scrolling.

## Motion & Performance

- **Motion:** Functional only, under 200ms. No perpetual animation or backdrop blur.
- **Resource rule:** Glass is drawn with static gradients, outlines and shadows only. Lists and source tabs build on demand.
