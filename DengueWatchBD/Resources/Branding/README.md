# App icon

`denguewatch_icon_crimson.svg` is the artwork as supplied.

`denguewatch_icon_crimson_baked.svg` is the same drawing with the group's
`transform-origin="512 512"` written out as explicit translates. macOS's SVG
renderer ignores `transform-origin` — it is a CSS property, not an SVG 1.1
attribute — so rendering the original put the artwork lower and smaller than
the design intends. The baked file is what `AppIcon1024.png` was rendered
from.

To regenerate: render the baked SVG at 1024×1024 and flatten away the alpha
channel. iOS rejects an app icon that carries one.
