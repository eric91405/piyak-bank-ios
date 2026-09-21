#!/usr/bin/env python3
"""Check every packaged ELF LOAD segment and uncompressed APK library for 16 KB alignment."""
import argparse
import struct
import zipfile
from pathlib import Path


def check(path: Path) -> int:
    count = 0
    with zipfile.ZipFile(path) as archive, path.open("rb") as raw:
        for entry in archive.infolist():
            if not entry.filename.endswith(".so"):
                continue
            data = archive.read(entry)
            if data[:4] != b"\x7fELF" or data[4] not in (1, 2) or data[5] not in (1, 2):
                raise ValueError(f"Invalid ELF: {entry.filename}")
            endian = "<" if data[5] == 1 else ">"
            is64 = data[4] == 2
            offset = struct.unpack_from(endian + ("Q" if is64 else "I"), data, 32 if is64 else 28)[0]
            size, number = struct.unpack_from(endian + "HH", data, 54 if is64 else 42)
            loads = 0
            for index in range(number):
                fields = struct.unpack_from(endian + ("IIQQQQQQ" if is64 else "IIIIIIII"), data, offset + index * size)
                if fields[0] == 1:
                    loads += 1
                    if fields[-1] < 16_384:
                        raise ValueError(f"ELF LOAD alignment {fields[-1]} < 16384: {entry.filename}")
            if not loads:
                raise ValueError(f"No ELF LOAD segments: {entry.filename}")
            if path.suffix == ".apk" and entry.compress_type == zipfile.ZIP_STORED:
                raw.seek(entry.header_offset)
                header = raw.read(30)
                name_size, extra_size = struct.unpack_from("<HH", header, 26)
                start = entry.header_offset + 30 + name_size + extra_size
                if start % 16_384:
                    raise ValueError(f"Uncompressed APK library is not ZIP aligned: {entry.filename}")
            count += 1
    print(f"PASS {path.name}: {count} native libraries support 16 KB alignment")
    return count


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archives", type=Path, nargs="+")
    for archive_path in parser.parse_args().archives:
        check(archive_path)
