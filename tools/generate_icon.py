"""Generate the PetPal brand mark assets.

The mark is the journal-+-paw motif locked in DECISIONS row 35: an open
journal spread (leaf/eye silhouette) with a paw print on the right
page. Single-line, monogram-feel, medium stroke weight.

Outputs (all under `assets/branding/`):
  icon-foreground.png       — graphite mark, transparent bg.
                              Adaptive launcher foreground (Android 8+)
                              and light-mode splash foreground.
  icon-foreground-dark.png  — warm-off-white mark, transparent bg.
                              Dark-mode splash foreground (Phase 5
                              task 5.4 — locked by user choice in the
                              dark-splash design question).
  icon-legacy.png           — graphite mark composited onto warm
                              off-white. Pre-API-26 launcher icon
                              fallback for Android 7.x.

The script renders at 4096x4096 and downsamples to 1024x1024 with
LANCZOS resampling so PIL's anti-aliasing produces clean edges at the
final size.

Re-run with: `python3 tools/generate_icon.py`
After regenerating, re-run the platform-icon generators:
  dart run flutter_launcher_icons
  dart run flutter_native_splash:create
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
# Render at 4x final resolution and downsample for clean anti-aliasing.
WORKING = 4096
FINAL = 1024
SCALE = WORKING // FINAL  # 4

# Brand colors (DECISIONS row 35).
GRAPHITE = (45, 52, 54, 255)             # PetPalColors.graphite (#2D3436)
WARM_OFF_WHITE = (247, 245, 242, 255)    # PetPalColors.warmOffWhite (#F7F5F2)
TRANSPARENT = (0, 0, 0, 0)

# Medium stroke weight per the user's choice in task 5.3.
STROKE = 80


def _scale(p: tuple[float, float]) -> tuple[int, int]:
    """Map a logical 1024-space coordinate to the working 4096 canvas."""
    return int(p[0] * SCALE), int(p[1] * SCALE)


def _line(
    draw: ImageDraw.ImageDraw,
    points: list[tuple[float, float]],
    *,
    ink: tuple[int, int, int, int],
    width: int = STROKE,
    closed: bool = False,
) -> None:
    """Polyline with rounded joints + caps. PIL's `joint='curve'` rounds
    corners; rounded caps are faked by overdrawing filled circles at
    each vertex (PIL's line() leaves square caps, which read harshly)."""
    pts = [_scale(p) for p in points]
    if closed:
        pts.append(pts[0])
    draw.line(pts, fill=ink, width=width, joint='curve')
    radius = width // 2
    for x, y in pts:
        draw.ellipse(
            (x - radius, y - radius, x + radius, y + radius),
            fill=ink,
        )


def _ellipse(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    rx: float,
    ry: float,
    *,
    ink: tuple[int, int, int, int],
    width: int = STROKE,
) -> None:
    cx, cy = _scale(center)
    rx_s = int(rx * SCALE)
    ry_s = int(ry * SCALE)
    draw.ellipse(
        (cx - rx_s, cy - ry_s, cx + rx_s, cy + ry_s),
        outline=ink,
        width=width,
    )


def render(ink: tuple[int, int, int, int]) -> Image.Image:
    """Render the journal-+-paw mark at WORKING resolution.

    `ink` is the stroke color. Use GRAPHITE for the light-mode mark
    and WARM_OFF_WHITE for the dark-mode mark; the geometry is
    identical, only the ink changes.
    """
    img = Image.new('RGBA', (WORKING, WORKING), TRANSPARENT)
    draw = ImageDraw.Draw(img)

    # ------------------------------------------------------------------
    # OPEN JOURNAL — leaf/eye silhouette
    # ------------------------------------------------------------------
    # Spine runs vertically through the center; spine endpoints sit at
    # the EXTREMES of the page outline (spine top is the highest point
    # of the mark; spine bottom is the lowest point). Outer corners sit
    # INSIDE that vertical range, with outer page edges bowing outward
    # at the midline. The result is an eye/leaf-shaped silhouette —
    # universally readable as "open book viewed face-on," with the
    # spine ridge running from peak to base.
    #
    # Iteration history:
    #  - v1: bottom corners converged at the spine bottom → cube.
    #  - v2: corners pulled OUTSIDE the spine in both axes → bowtie.
    #  - v3 (this): corners pulled INSIDE the spine extremes → leaf.
    spine_top = (512, 285)
    spine_bottom = (512, 765)

    lp_top_outer = (180, 360)
    lp_bottom_outer = (180, 690)
    rp_top_outer = (844, 360)
    rp_bottom_outer = (844, 690)

    # Top edges — slope down from spine peak to outer top corners.
    _line(draw, [spine_top, lp_top_outer], ink=ink)
    _line(draw, [spine_top, rp_top_outer], ink=ink)

    # Bottom edges — mirrored.
    _line(draw, [spine_bottom, lp_bottom_outer], ink=ink)
    _line(draw, [spine_bottom, rp_bottom_outer], ink=ink)

    # Outer page edges — bowed outward at midline for natural paper curl.
    _line(draw, [lp_top_outer, (135, 525), lp_bottom_outer], ink=ink)
    _line(draw, [rp_top_outer, (889, 525), rp_bottom_outer], ink=ink)

    # Spine — slightly thinner; reads as interior detail.
    _line(draw, [spine_top, spine_bottom], ink=ink, width=STROKE - 12)

    # Text lines on left page — lighter stroke; suggests "in-use journal".
    text_stroke = STROKE // 3
    text_lines = [
        [(245, 460), (445, 452)],
        [(245, 510), (445, 502)],
        [(245, 560), (405, 552)],
    ]
    for line_pts in text_lines:
        _line(draw, line_pts, ink=ink, width=text_stroke)

    # ------------------------------------------------------------------
    # PAW PRINT — right page
    # ------------------------------------------------------------------
    # 1 palm pad (wider-than-tall) + 4 oval toes arcing above. Toes
    # ~50% of the palm so the paw reads quickly at small sizes.
    _ellipse(draw, center=(690, 605), rx=82, ry=64, ink=ink)

    toes = [
        ((605, 510), 32, 40),  # outer-left
        ((660, 470), 30, 40),  # inner-left, higher
        ((720, 470), 30, 40),  # inner-right, higher
        ((775, 510), 32, 40),  # outer-right
    ]
    for center, rx, ry in toes:
        _ellipse(draw, center=center, rx=rx, ry=ry, ink=ink)

    return img


def _composite_on_warm_off_white(foreground: Image.Image) -> Image.Image:
    """Bakes the foreground onto a warm off-white square for the legacy
    (pre-Android-8.0) launcher icon. API 24-25 doesn't read adaptive
    icon XML; without a composited fallback the transparent foreground
    would render against whatever background the launcher chooses."""
    bg = Image.new('RGBA', foreground.size, WARM_OFF_WHITE)
    bg.alpha_composite(foreground)
    return bg.convert('RGB')


def _render_to_final(ink: tuple[int, int, int, int]) -> Image.Image:
    img = render(ink)
    return img.resize((FINAL, FINAL), Image.Resampling.LANCZOS)


def main() -> None:
    branding = Path(__file__).resolve().parent.parent / 'assets' / 'branding'
    branding.mkdir(parents=True, exist_ok=True)

    light = _render_to_final(GRAPHITE)
    light_path = branding / 'icon-foreground.png'
    light.save(light_path, 'PNG')
    print(f'wrote {light_path} ({light_path.stat().st_size:,} bytes)')

    dark = _render_to_final(WARM_OFF_WHITE)
    dark_path = branding / 'icon-foreground-dark.png'
    dark.save(dark_path, 'PNG')
    print(f'wrote {dark_path} ({dark_path.stat().st_size:,} bytes)')

    legacy = _composite_on_warm_off_white(light)
    legacy_path = branding / 'icon-legacy.png'
    legacy.save(legacy_path, 'PNG')
    print(f'wrote {legacy_path} ({legacy_path.stat().st_size:,} bytes)')


if __name__ == '__main__':
    main()
