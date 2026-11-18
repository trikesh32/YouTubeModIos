"""Mach-O helpers adapted from trikesh32/TikTokModIos (MIT)."""
import struct
MAGIC64=b"\xcf\xfa\xed\xfe"
LOAD_DYLIB=0xc
LIBRARY_PATH="@executable_path/Frameworks/YouTubeMod.dylib"

def thin_arm64(data):
    """Select the generic ARM64 slice, validating every fat-table range first."""
    if data[:4] == MAGIC64:
        return data
    if data[:4] != b"\xca\xfe\xba\xbe" or len(data) < 8:
        raise ValueError('Unsupported universal Mach-O format')
    count = struct.unpack_from('>I', data, 4)[0]
    if not 1 <= count <= 32 or 8 + count * 20 > len(data):
        raise ValueError('Invalid fat architecture table')
    slices = []
    selected = []
    for i in range(count):
        cpu, subtype, offset, size, align = struct.unpack_from('>IIIII', data, 8 + i * 20)
        if align > 30 or offset % (1 << align) or offset < 8 + count * 20 or size < 32 or offset + size > len(data):
            raise ValueError('Invalid fat slice bounds/alignment')
        if any(offset < end and offset + size > start for start, end in slices):
            raise ValueError('Overlapping fat slices')
        slices.append((offset, offset + size))
        if cpu == 0x100000c and subtype == 0:
            selected.append(data[offset:offset + size])
    if len(selected) != 1 or selected[0][:4] != MAGIC64 or struct.unpack_from('<II', selected[0], 4) != (0x100000c, 0):
        raise ValueError('Expected exactly one matching generic ARM64 slice')
    check_decrypted(selected[0])
    return selected[0]

def commands(data):
    if len(data) < 32 or data[:4] != MAGIC64:
        raise ValueError("Expected a thin 64-bit little-endian Mach-O")
    count, size = struct.unpack_from("<II", data, 16)
    end = 32 + size
    if end > len(data) or count > size // 8:
        raise ValueError("Invalid load command bounds")
    pos = 32
    result = []
    for _ in range(count):
        if pos + 8 > end:
            raise ValueError("Truncated load command")
        cmd, length = struct.unpack_from("<II", data, pos)
        if length < 8 or length % 8 or pos + length > end:
            raise ValueError("Invalid load command size")
        result.append((cmd, pos, length))
        pos += length
    if pos != end:
        raise ValueError("Load command size mismatch")
    return result

def inject(data, library=LIBRARY_PATH):
    table = commands(data)
    if struct.unpack_from("<I", data, 4)[0] != 0x100000C:
        raise ValueError("Only ARM64 executables are supported")
    first_section = len(data)
    for cmd, pos, size in table:
        if cmd in (0xC, 0x18 | 0x80000000, 0x1F | 0x80000000):
            offset = struct.unpack_from("<I", data, pos + 8)[0]
            if offset >= size:
                raise ValueError("Invalid dylib path offset")
            name = data[pos + offset:pos + size].split(b"\0", 1)[0]
            if name == library.encode():
                raise ValueError("Module is already injected")
        if cmd == 0x19:
            if size < 72:
                raise ValueError("Invalid segment command")
            sections = struct.unpack_from("<I", data, pos + 64)[0]
            if 72 + sections * 80 > size:
                raise ValueError("Invalid section table")
            for index in range(sections):
                offset = struct.unpack_from("<I", data, pos + 72 + index * 80 + 48)[0]
                if offset:
                    first_section = min(first_section, offset)
    count, size = struct.unpack_from("<II", data, 16)
    name = library.encode() + b"\0"
    length = (24 + len(name) + 7) & ~7
    end = 32 + size
    if end + length > first_section or any(data[end:end + length]):
        raise ValueError("No verified zero-filled header padding for injection")
    command = struct.pack("<6I", LOAD_DYLIB, length, 24, 0, 0x10000, 0x10000) + name
    output = bytearray(data)
    output[end:end + length] = command.ljust(length, b"\0")
    struct.pack_into("<II", output, 16, count + 1, size + length)
    return bytes(output)

def check_decrypted(data):
    for cmd, pos, size in commands(data):
        if cmd in (0x21, 0x2C):
            if size < 20 or struct.unpack_from("<I", data, pos + 16)[0] != 0:
                raise ValueError("Encrypted or malformed Mach-O in input")
