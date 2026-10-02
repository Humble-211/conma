#!/usr/bin/env python3
"""Writes a 1024x1024 placeholder app icon (orange field, white beam-and-post mark) without Pillow."""
import pathlib, struct, zlib

SIZE = 1024
BG = (0xD9, 0x65, 0x1F)
FG = (0xFF, 0xFF, 0xFF)
OUT = pathlib.Path(__file__).resolve().parents[1] / "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

def inside_mark(x, y):
    # Horizontal beam
    if 192 <= x < 832 and 300 <= y < 420:
        return True
    # Two posts
    if (272 <= x < 392 or 632 <= x < 752) and 420 <= y < 760:
        return True
    return False

def png_chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

def main():
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # filter: none
        for x in range(SIZE):
            rows.extend(FG if inside_mark(x, y) else BG)
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + png_chunk(b"IEND", b"")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png)
    print(f"wrote {OUT} ({len(png)} bytes)")

if __name__ == "__main__":
    main()
