"""Generate the PetPal adaptive launcher icon foreground.

The mark is the journal-+-paw motif locked in DECISIONS row 35: an open
journal spread with a paw print sitting on the right page. Single-line,
monogram-feel, medium stroke weight (DECISIONS row 38 follow-up: row
locks composition direction + stroke weight via Phase 5 task 5.3).

The script renders at 4096x4096 and downsamples to 1024x1024 with
bicubic resampling so PIL's anti-aliasing produces clean edges at the
final size. Output is placed at `assets/branding/icon-foreground.png`
where `flutter_launcher_icons` reads it during `dart run` to generate
the per-density Android assets.

Re-run with: `python3 tools/generate_icon.py`
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

# Graphite ink (PetPalColors.graphite, DECISIONS row 35).
GRAPHITE = (45, 52, 54, 255)
# Foreground asset is transparent — the launcher composes it on top of
# the warm off-white background tile we set in pubspec.
TRANSPARENT = (0, 0, 0, 0)

# Medium stroke weight per the user's choice in task 5.3 (~2% of the
# working canvas; ~0.5% of the final canvas; scales down readably to
# notification-badge sizes).
STROKE = 80


def _scale(p: tuple[float, float]) -> tuple[int, int]:
    """Map a logical 1024-space coordinate to the working 4096 canvas."""
    return int(p[0] * SCALE), int(p[1] * SCALE)


def _line(
    draw: ImageDraw.ImageDraw,
    points: list[tuple[float, float]],
    *,
    width: int = STROKE,
    closed: bool = False,
) -> None:
    """Polyline with rounded joints + caps. PIL's `joint='curve'` rounds
    the corners and `capstyle='round'` would too if we used arcs — we
    fake it by overdrawing rounded endpoints."""
    pts = [_scale(p) for p in points]
    if closed:
        pts.append(pts[0])
    draw.line(pts, fill=GRAPHITE, width=width, joint='curve')
    # Round the line caps by drawing small filled circles at each
    # vertex. PIL's line() leaves square caps which read harshly at
    # icon scale.
    radius = width // 2
    for x, y in pts:
        draw.ellipse(
            (x - radius, y - radius, x + radius, y + radius),
            fill=GRAPHITE,
        )


def _circle(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    radius: float,
    *,
    width: int = STROKE,
    fill: tuple[int, int, int, int] | None = None,
) -> None:
    cx, cy = _scale(center)
    r = int(radius * SCALE)
    box = (cx - r, cy - r, cx + r, cy + r)
    if fill is not None:
        draw.ellipse(box, fill=fill)
    else:
        draw.ellipse(box, outline=GRAPHITE, width=width)


def _ellipse(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    rx: float,
    ry: float,
    *,
    width: int = STROKE,
) -> None:
    cx, cy = _scale(center)
    rx_s = int(rx * SCALE)
    ry_s = int(ry * SCALE)
    draw.ellipse(
        (cx - rx_s, cy - ry_s, cx + rx_s, cy + ry_s),
        outline=GRAPHITE,
        width=width,
    )


def render() -> Image.Image:
    img = Image.new('RGBA', (WORKING, WORKING), TRANSPARENT)
    draw = ImageDraw.Draw(img)

    # ------------------------------------------------------------------
    # OPEN JOURNAL — leaf/eye silhouette
    # ------------------------------------------------------------------
    # Spine runs vertically through the center; spine endpoints sit at
    # the EXTREMES of the page outline (spine top is the highest point
    # of the mark; spine bottom is the lowest point). Outer corners sit
    # INSIDE that vertical range, with outer page edges bowing
    # outward at the midline. The result is an eye/leaf-shaped
    # silhouette — universally readable as "open book viewed
    # face-on," with the spine ridge running from peak to base.
    #
    # Iteration history:
    #  - v1: bottom corners converged at the spine bottom → isometric
    #    cube reading.
    #  - v2: corners pulled OUTSIDE the spine in both axes → bowtie.
    #  - v3 (this): corners pulled INSIDE the spine extremes →
    #    leaf/eye silhouette.
    spine_top = (512, 285)
    spine_bottom = (512, 765)

    # Outer corners — INSIDE the spine extremes vertically, well out
    # to the sides horizontally.
    lp_top_outer = (180, 360)
    lp_bottom_outer = (180, 690)
    rp_top_outer = (844, 360)
    rp_bottom_outer = (844, 690)

    # Top edge of each page — slope down from spine peak to the outer
    # top corner. The eye reads this slope as the V where the open
    # book pages meet at the spine.
    _line(draw, [spine_top, lp_top_outer], closed=False)
    _line(draw, [spine_top, rp_top_outer], closed=False)

    # Bottom edge of each page — slope up from spine base to the
    # outer bottom corner. Mirrors the top.
    _line(draw, [spine_bottom, lp_bottom_outer], closed=False)
    _line(draw, [spine_bottom, rp_bottom_outer], closed=False)

    # Outer page edges — bowed outward at the page midline (~525) so
    # the pages read as having natural paper curl, not straight cuts.
    _line(draw, [lp_top_outer, (135, 525), lp_bottom_outer], closed=False)
    _line(draw, [rp_top_outer, (889, 525), rp_bottom_outer], closed=False)

    # Spine — slightly thinner so the binding reads as interior detail.
    _line(draw, [spine_top, spine_bottom], width=STROKE - 12)

    # A few text lines on the left page suggesting "journal in use".
    # Lighter stroke weight than the page outline so they read as
    # interior detail. Slight inward slope (lines slanting up toward
    # the spine) mirrors a notebook held at a slight reading angle.
    text_stroke = STROKE // 3
    text_lines = [
        [(245, 460), (445, 452)],
        [(245, 510), (445, 502)],
        [(245, 560), (405, 552)],
    ]
    for line_pts in text_lines:
        _line(draw, line_pts, width=text_stroke)

    # ------------------------------------------------------------------
    # PAW PRINT — sits on the right page
    # ------------------------------------------------------------------
    # 1 palm pad + 4 oval toes arcing across the top. Toes are sized
    # at ~50% of the palm pad so the paw reads quickly at small icon
    # sizes (an earlier iteration had toes too small relative to the
    # palm and the silhouette read as "circle with dots"). Anchored
    # around (690, 555) on the right page.

    # Palm pad — wider-than-tall.
    _ellipse(draw, center=(690, 605), rx=82, ry=64)

    # Four toes arcing across the top of the palm. Inner two sit
    # higher than the outer two — typical paw silhouette.
    toes = [
        ((605, 510), 32, 40),  # outer-left, slightly lower
        ((660, 470), 30, 40),  # inner-left, higher
        ((720, 470), 30, 40),  # inner-right, higher
        ((775, 510), 32, 40),  # outer-right, slightly lower
    ]
    for center, rx, ry in toes:
        _ellipse(draw, center=center, rx=rx, ry=ry)

    return img


def _composite_on_warm_off_white(foreground: Image.Image) -> Image.Image:
    """Bakes the foreground onto a warm off-white square for the legacy
    (pre-Android-8.0) launcher icon. API 24-25 doesn't read adaptive
    icon XML; without a composited fallback the transparent foreground
    would render against whatever background the launcher chooses."""
    bg = Image.new('RGBA', foreground.size, (247, 245, 242, 255))  # #F7F5F2
    bg.alpha_composite(foreground)
    return bg.convert('RGB')


def main() -> None:
    branding = Path(__file__).resolve().parent.parent / 'assets' / 'branding'
    branding.mkdir(parents=True, exist_ok=True)

    img = render()
    img = img.resize((FINAL, FINAL), Image.Resampling.LANCZOS)

    foreground_path = branding / 'icon-foreground.png'
    img.save(foreground_path, 'PNG')
    print(f'wrote {foreground_path} ({foreground_path.stat().st_size:,} bytes)')

    legacy_path = branding / 'icon-legacy.png'
    legacy = _composite_on_warm_off_white(img)
    legacy.save(legacy_path, 'PNG')
    print(f'wrote {legacy_path} ({legacy_path.stat().st_size:,} bytes)')


if __name__ == '__main__':
    main()
