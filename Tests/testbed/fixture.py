import subprocess
import sys

from PIL import Image, ImageDraw

WIDTH, HEIGHT = 640, 360


def main():
    out_dir, ffmpeg, base = sys.argv[1], sys.argv[2], sys.argv[3].rstrip("/")
    subprocess.run([
        ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", f"testsrc=size={WIDTH}x{HEIGHT}:rate=25:duration=4",
        "-f", "lavfi", "-i", "sine=frequency=440:duration=4",
        "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-profile:v", "main",
        "-c:a", "aac", "-b:a", "64k", "-shortest", "-movflags", "+faststart",
        f"{out_dir}/video.mp4",
    ], check=True)
    poster = Image.new("RGB", (WIDTH, HEIGHT), (30, 90, 160))
    draw = ImageDraw.Draw(poster)
    draw.rectangle((40, 40, WIDTH - 40, HEIGHT - 40), outline=(255, 255, 255), width=6)
    draw.polygon([(270, 120), (270, 240), (380, 180)], fill=(255, 255, 255))
    poster.save(f"{out_dir}/poster.png")
    title = "Testbed sample video"
    html = f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>{title}</title>
<meta property="og:type" content="video.other">
<meta property="og:title" content="{title}">
<meta property="og:description" content="Four second H.264 test clip served by the gomuks testbed">
<meta property="og:url" content="{base}/video.html">
<meta property="og:image" content="{base}/poster.png">
<meta property="og:image:type" content="image/png">
<meta property="og:image:width" content="{WIDTH}">
<meta property="og:image:height" content="{HEIGHT}">
<meta property="og:video" content="{base}/video.mp4">
<meta property="og:video:type" content="video/mp4">
<meta property="og:video:width" content="{WIDTH}">
<meta property="og:video:height" content="{HEIGHT}">
</head>
<body>
<h1>{title}</h1>
<video controls width="{WIDTH}" height="{HEIGHT}" poster="{base}/poster.png">
<source src="{base}/video.mp4" type="video/mp4">
</video>
</body>
</html>
"""
    with open(f"{out_dir}/video.html", "w") as f:
        f.write(html)


if __name__ == "__main__":
    main()
