# App icon

`denguewatch_icon_source.png` is the artwork as supplied, and it arrived in
exactly the shape an iOS icon wants: 1024×1024, full-bleed, with every pixel
opaque.

`AppIcon1024.png` in the asset catalogue is that file with its alpha channel
dropped and nothing else changed — iOS rejects an icon carrying one, even an
unused one. No crop, no resample; the two are pixel-identical in RGB.

If the artwork is ever replaced, check three things before shipping it:

- **1024×1024.** Anything else has to be resampled.
- **Full-bleed, square, no rounded corners.** iOS applies its own corner mask.
  Artwork that carries its own rounding gets rounded twice, and the
  transparent corners flatten to visible wedges.
- **No transparency.** Not just "no alpha channel" — check that no pixel is
  actually non-opaque, since a fully opaque alpha channel is harmless and can
  simply be dropped.
