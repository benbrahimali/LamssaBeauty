"""
Run this script once to generate the LAMSSA app icon PNG.
Requires: pip install Pillow
Then run: python generate_icon.py
Then run: dart run flutter_launcher_icons
"""
try:
    from PIL import Image, ImageDraw, ImageFont
    import math

    SIZE = 1024

    # Background — deep dark navy
    img = Image.new('RGBA', (SIZE, SIZE), (8, 8, 16, 255))
    draw = ImageDraw.Draw(img)

    # Subtle radial glow (gold)
    for r in range(200, 0, -2):
        alpha = int(30 * (1 - r / 200))
        color = (201, 168, 76, alpha)
        draw.ellipse(
            [(SIZE//2 - r*2, SIZE//2 - r*2), (SIZE//2 + r*2, SIZE//2 + r*2)],
            fill=color
        )

    # Gold circle background
    margin = 120
    draw.ellipse(
        [(margin, margin), (SIZE - margin, SIZE - margin)],
        fill=(201, 168, 76, 255)
    )

    # Dark inner circle
    inner_margin = 160
    draw.ellipse(
        [(inner_margin, inner_margin), (SIZE - inner_margin, SIZE - inner_margin)],
        fill=(8, 8, 16, 255)
    )

    # Gold ring border
    ring_w = 8
    draw.ellipse(
        [(inner_margin + 20, inner_margin + 20), (SIZE - inner_margin - 20, SIZE - inner_margin - 20)],
        outline=(201, 168, 76, 200),
        width=ring_w
    )

    # "L" letter in gold
    # Draw a bold L manually using rectangles
    gold = (201, 168, 76, 255)
    bar_w = 90   # stroke width
    # Vertical bar of L
    draw.rectangle([(420, 280), (420 + bar_w, 680)], fill=gold)
    # Horizontal bar of L
    draw.rectangle([(420, 680 - bar_w), (620, 680)], fill=gold)

    # Save
    img.save('assets/images/app_icon.png')
    img.save('assets/images/app_icon_fg.png')
    print("✅ app_icon.png created successfully!")
    print("Now run: dart run flutter_launcher_icons")

except ImportError:
    print("❌ Pillow not found. Install it: pip install Pillow")
    print("   Or create your own 1024x1024 PNG at assets/images/app_icon.png")
    print("   Then run: dart run flutter_launcher_icons")
