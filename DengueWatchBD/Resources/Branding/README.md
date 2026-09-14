# App icon

`denguewatch_icon_source.png` is the artwork as supplied: 1254×1254, with
transparency, drawn as a rounded tile floating in transparent margins.

`AppIcon1024.png` in the asset catalogue is derived from it, and the
derivation matters:

- **Cropped inside the tile's rounded corners.** iOS applies its own corner
  mask. Shipping the artwork's own rounding would round the icon twice and
  leave pale wedges where the transparent corners flattened. The crop is the
  largest square whose every edge pixel is solid — measured by probing the
  alpha channel, not estimated — which keeps 82.8% of the tile.
- **Scaled to 1024×1024 and flattened to RGB.** iOS rejects an app icon
  carrying an alpha channel.

To regenerate after an artwork change, re-probe the corners rather than
reusing these numbers: they are specific to this file's rounding radius.
