from PIL import Image, ImageDraw

color = (230, 230, 230, 255)
color = (20, 20, 20, 255)
scale = 4

def points(values):
    return [(x * scale, y * scale) for x, y in values]

# Up/down triangles: 40 × 56 px
image = Image.new("RGBA", (40 * scale, 56 * scale), (0, 0, 0, 0)) # type: ignore
draw = ImageDraw.Draw(image)
draw.polygon(points([(20, 4), (7, 22), (33, 22)]), fill=color)
draw.polygon(points([(7, 34), (33, 34), (20, 52)]), fill=color)
image.resize((40, 56), Image.Resampling.LANCZOS).save("graphics/move-up-down.png")

# Target dot: 40 × 40 px
image = Image.new("RGBA", (40 * scale, 40 * scale), (0, 0, 0, 0)) # type: ignore
ImageDraw.Draw(image).ellipse((7*scale, 7*scale, 33 * scale, 33 * scale), fill=color)
image.resize((40, 40), Image.Resampling.LANCZOS).save("graphics/move-target.png")