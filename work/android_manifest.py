"""Add network permissions and a launcher label to the local runner template."""

from pathlib import Path
from struct import pack, pack_into, unpack_from
from zipfile import ZipFile


def chunks(data):
    offset = 8
    while offset < len(data):
        kind, _, size = unpack_from("<HHI", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid binary XML chunk")
        yield kind, bytearray(data[offset : offset + size])
        offset += size


def update_manifest(original):
    nodes = list(chunks(original))
    kind, pool = nodes[0]
    count, styles, flags, start, styles_start = unpack_from("<IIIII", pool, 8)
    if kind != 1 or styles or flags or styles_start or start != 28 + count * 4:
        raise ValueError("Unsupported string-pool layout")

    offsets = list(unpack_from(f"<{count}I", pool, 28))
    data = pool[start:]
    strings = {}
    for index, offset in enumerate(offsets):
        length = unpack_from("<H", data, offset)[0]
        value = data[offset + 2 : offset + 2 + 2 * length].decode("utf-16le")
        strings.setdefault(value, index)

    def add_string(value):
        if value not in strings:
            strings[value] = len(offsets)
            offsets.append(len(data))
            encoded = value.encode("utf-16le")
            data.extend(pack("<H", len(encoded) // 2) + encoded + b"\0\0")
        return strings[value]

    permissions = [add_string("android.permission." + name) for name in (
        "ACCESS_NETWORK_STATE", "INTERNET"
    )]
    label = add_string("Mega Maker")
    padding = b"\0" * (-len(data) % 4)
    new_start = 28 + len(offsets) * 4
    pool = pack("<HHIIIIII", 1, 28, new_start + len(data) + len(padding),
                len(offsets), 0, 0, new_start, 0)
    pool += pack(f"<{len(offsets)}I", *offsets) + data + padding

    result = bytearray(pool)
    added_permissions = False
    labels_changed = 0
    for index, (kind, node) in enumerate(nodes[1:], 1):
        if kind == 0x102:
            tag = unpack_from("<I", node, 20)[0]
            attr_start, attr_size, attr_count = unpack_from("<HHH", node, 24)
            if attr_size != 20:
                raise ValueError("Unexpected manifest attribute size")
            if tag == strings["uses-permission"] and not added_permissions:
                end_kind, end_node = nodes[index + 1]
                if end_kind != 0x103 or attr_count != 1:
                    raise ValueError("Could not clone the permission element")
                for permission in permissions:
                    clone = bytearray(node)
                    offset = 16 + attr_start
                    pack_into("<I", clone, offset + 8, permission)
                    pack_into("<I", clone, offset + 16, permission)
                    result.extend(clone + end_node)
                added_permissions = True
            if tag in (strings["application"], strings["activity"], strings["uses-sdk"]):
                for attr in range(attr_count):
                    offset = 16 + attr_start + attr * attr_size
                    name = unpack_from("<I", node, offset + 4)[0]
                    if name == strings["label"]:
                        pack_into("<IHBBI", node, offset + 8, label, 8, 0, 3, label)
                        labels_changed += 1
                    if name == strings["minSdkVersion"]:
                        pack_into("<I", node, offset + 16, 24)
        result.extend(node)

    if not added_permissions or labels_changed != 2:
        raise ValueError("Missing expected template permission or label nodes")
    return pack("<HHI", 3, 8, 8 + len(result)) + result


with ZipFile("work/tools/runner-2024.14.apk") as runner:
    manifest = update_manifest(runner.read("AndroidManifest.xml"))
Path("work/AndroidManifest.xml").write_bytes(manifest)
