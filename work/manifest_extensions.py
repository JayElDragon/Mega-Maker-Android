"""Register Android extension classes in a GameMaker runner's binary manifest.

The runner reads YYNumExtensionClasses / YYExtensionClass<N> from the
application <meta-data>, then instantiates com.company.game.<Name>.
Also lets the game draw under display cutouts so widescreen fills the panel.
"""

import argparse
from pathlib import Path
from struct import pack, pack_into, unpack_from
from zipfile import ZipFile

TYPE_STRING, TYPE_INT_DEC = 0x03, 0x10


def chunks(data):
    offset = 8
    while offset < len(data):
        kind, _, size = unpack_from("<HHI", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid binary XML chunk")
        yield kind, bytearray(data[offset:offset + size])
        offset += size


def patch(original, classes):
    nodes = list(chunks(original))
    kind, pool = nodes[0]
    count, styles, flags, start, styles_start = unpack_from("<IIIII", pool, 8)
    if kind != 1 or styles or flags or styles_start or start != 28 + count * 4:
        raise ValueError("Unsupported string-pool layout")
    offsets = list(unpack_from(f"<{count}I", pool, 28))
    data = pool[start:]
    lookup, values = {}, []
    for index, offset in enumerate(offsets):
        length = unpack_from("<H", data, offset)[0]
        value = data[offset + 2:offset + 2 + 2 * length].decode("utf-16le")
        values.append(value)
        lookup.setdefault(value, index)

    def string(value):
        if value not in lookup:
            lookup[value] = len(offsets)
            offsets.append(len(data))
            values.append(value)
            encoded = value.encode("utf-16le")
            data.extend(pack("<H", len(encoded) // 2) + encoded + b"\0\0")
        return lookup[value]

    def attrs(node):
        attr_start, attr_size, attr_count = unpack_from("<HHH", node, 24)
        for attr in range(attr_count):
            yield 16 + attr_start + attr * attr_size

    def meta_name(node):
        for offset in attrs(node):
            if unpack_from("<I", node, offset + 4)[0] == lookup["name"]:
                return values[unpack_from("<I", node, offset + 8)[0]]
        return None

    def set_value(node, kind, value):
        for offset in attrs(node):
            if unpack_from("<I", node, offset + 4)[0] == lookup["value"]:
                raw = value if kind == TYPE_STRING else 0xFFFFFFFF
                pack_into("<IHBBI", node, offset + 8, raw, 8, 0, kind, value)
                return
        raise ValueError("meta-data node has no value attribute")

    def set_name(node, name):
        for offset in attrs(node):
            if unpack_from("<I", node, offset + 4)[0] == lookup["name"]:
                pack_into("<I", node, offset + 8, name)
                pack_into("<I", node, offset + 16, name)

    class_ids = [(string(f"YYExtensionClass{i}"), string(name)) for i, name in enumerate(classes)]
    short_edges = string("LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES")
    meta_tag = lookup["meta-data"]

    result_nodes, template, done = [], None, set()
    for index, (kind, node) in enumerate(nodes[1:], 1):
        if kind == 0x102 and unpack_from("<I", node, 20)[0] == meta_tag:
            name = meta_name(node)
            if name in {f"YYExtensionClass{i}" for i in range(64)}:
                # Drop stale entries; the end tag that follows is dropped too.
                done.add(("skip", index + 1))
                continue
            if name == "YYDisplayLayout":
                set_value(node, TYPE_STRING, short_edges)
                template = (bytearray(node), nodes[index + 1][1])
            if name == "YYNumExtensionClasses":
                set_value(node, TYPE_INT_DEC, len(classes))
                result_nodes.append((kind, node))
                result_nodes.append(nodes[index + 1])
                for name_id, value_id in class_ids:
                    clone = bytearray(template[0])
                    set_name(clone, name_id)
                    set_value(clone, TYPE_STRING, value_id)
                    result_nodes.append((0x102, clone))
                    result_nodes.append((0x103, bytearray(template[1])))
                done.add(("skip", index + 1))
                done.add("count")
                continue
        if ("skip", index) in done:
            continue
        result_nodes.append((kind, node))

    if "count" not in done or template is None:
        raise ValueError("Manifest lacks YYNumExtensionClasses/YYDisplayLayout meta-data")

    padding = b"\0" * (-len(data) % 4)
    new_start = 28 + len(offsets) * 4
    out = bytearray(pack("<HHIIIIII", 1, 28, new_start + len(data) + len(padding),
                         len(offsets), 0, 0, new_start, 0))
    out += pack(f"<{len(offsets)}I", *offsets) + data + padding
    for _, node in result_nodes:
        out += node
    return pack("<HHI", 3, 8, 8 + len(out)) + out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("classes", nargs="+")
    args = parser.parse_args()
    with ZipFile(args.apk) as apk:
        manifest = apk.read("AndroidManifest.xml")
    args.output.write_bytes(patch(manifest, args.classes))


if __name__ == "__main__":
    main()
