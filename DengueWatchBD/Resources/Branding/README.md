# App icon

`AppIcon1024.png` in the asset catalogue is a copy of
`denguewatch_icon_crimson.png`, supplied as artwork. It is already what iOS
needs: 1024×1024, RGB, no alpha channel — iOS rejects an app icon that
carries one.

`denguewatch_icon_crimson.svg` is the vector the PNG was drawn from, kept for
future edits.

A note for anyone regenerating the PNG from the SVG: the artwork group uses
`transform-origin`, and renderers differ on it — it is a CSS property rather
than an SVG 1.1 attribute. Writing that transform out as explicit translates
produces a visibly different composition from the supplied PNG, so it is the
wrong thing to do here. Render the SVG as written, and compare the result
against this PNG before shipping it.
