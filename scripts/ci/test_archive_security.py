#!/usr/bin/env python3
"""Focused archive preflight checks for the Python bridge."""

import tempfile
import zipfile
import struct
import zlib
import os
import socket
import subprocess
from binascii import crc32
from pathlib import Path

from PIL import Image

from docling_bridge import security
from docling_bridge.security import (
    validate_archive_file,
    validate_file_signature,
    validate_image_file,
    validate_pdf_file,
)


def make_zip(path: Path, entries: dict[str, bytes]) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)


def expect_rejected(path: Path, expected: str, validator=validate_archive_file) -> None:
    try:
        validator(path)
    except ValueError as error:
        message = str(error)
        if expected not in message:
            raise AssertionError(f"expected {expected!r} in {message!r}") from error
        return
    raise AssertionError(f"expected {path} to be rejected")


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc32(kind + data) & 0xFFFFFFFF)


def make_declared_size_png(path: Path, width: int, height: int) -> None:
    payload = b"\x89PNG\r\n\x1a\n"
    payload += png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    payload += png_chunk(b"IDAT", zlib.compress(b""))
    payload += png_chunk(b"IEND", b"")
    path.write_bytes(payload)


def make_minimal_pdf(path: Path, media_box_side: int) -> None:
    objects = [
        b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
        b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
        f"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {media_box_side} {media_box_side}] >>\nendobj\n".encode(),
    ]
    data = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for obj in objects:
        offsets.append(len(data))
        data.extend(obj)
    xref_offset = len(data)
    data.extend(f"xref\n0 {len(objects) + 1}\n".encode())
    data.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        data.extend(f"{offset:010d} 00000 n \n".encode())
    data.extend(
        f"trailer\n<< /Root 1 0 R /Size {len(objects) + 1} >>\nstartxref\n{xref_offset}\n%%EOF\n".encode()
    )
    path.write_bytes(data)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="upmarket-archive-security-") as temp:
        root = Path(temp)

        valid = root / "valid.zip"
        make_zip(valid, {"a.txt": b"hello", "folder/b.txt": b"world"})
        validate_archive_file(valid)

        traversal = root / "traversal.zip"
        make_zip(traversal, {"../escape.txt": b"bad"})
        expect_rejected(traversal, "unsafe file paths")

        nested = root / "nested.zip"
        make_zip(nested, {"inner.zip": b"not really zip, still disallowed"})
        expect_rejected(nested, "Nested ZIP")

        ratio = root / "ratio.zip"
        make_zip(ratio, {"huge.txt": b"0" * (2 * 1024 * 1024)})
        expect_rejected(ratio, "compression ratio")

        many = root / "many.zip"
        make_zip(many, {f"{index}.txt": b"x" for index in range(1001)})
        expect_rejected(many, "too many files")

        valid_image = root / "valid.png"
        Image.new("RGB", (16, 16), "white").save(valid_image)
        validate_image_file(valid_image)

        huge_image = root / "huge.png"
        make_declared_size_png(huge_image, 40_000, 1)
        expect_rejected(huge_image, "Image dimensions", validate_image_file)

        huge_pdf = root / "huge.pdf"
        make_minimal_pdf(huge_pdf, 20_000)
        expect_rejected(huge_pdf, "PDF page dimensions", validate_pdf_file)

        disguised_pdf = root / "fake.pdf"
        disguised_pdf.write_bytes(b"\x89PNG\r\n\x1a\n")
        expect_rejected(disguised_pdf, "does not match PDF", validate_file_signature)

        disguised_image = root / "fake.png"
        disguised_image.write_bytes(b"%PDF-1.4\n")
        expect_rejected(disguised_image, "does not match image", validate_file_signature)

        binary_text = root / "fake.csv"
        binary_text.write_bytes(b"a,b\x00c,d")
        expect_rejected(binary_text, "binary data", validate_file_signature)

        hostile_xml = root / "hostile.xml"
        hostile_xml.write_text("<!DOCTYPE x [<!ENTITY bomb 'x'>]><x>&bomb;</x>")
        expect_rejected(hostile_xml, "DTD or entity", validate_file_signature)

        os.environ["UPMARKET_RUNTIME_SANDBOX"] = "1"
        os.environ["UPMARKET_ALLOW_NETWORK"] = "0"
        security.install_runtime_sandbox()

        try:
            subprocess.run(["/usr/bin/true"], check=False)
        except PermissionError:
            pass
        else:
            raise AssertionError("runtime sandbox should block subprocess launch")

        try:
            socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        except PermissionError:
            pass
        else:
            raise AssertionError("runtime sandbox should block sockets during conversion")

    print("ok: archive security checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
