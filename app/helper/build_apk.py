#!/usr/bin/env python3
"""Build a minimal APK without aapt2: binary XML manifest + dex + zip + sign."""

import struct, os, zipfile

strings = []
str_index = {}

def add_str(s):
    if s not in str_index:
        str_index[s] = len(strings)
        strings.append(s)
    return str_index[s]

def chunk(t, header_size, payload):
    return struct.pack('<HHI', t, header_size, 8 + len(payload)) + payload

def string_pool():
    data = b''
    offsets = []
    for s in strings:
        enc = s.encode('utf-16-le')
        b = struct.pack('<H', len(s)) + enc + b'\x00\x00'
        offsets.append(len(data))
        data += b
    while len(data) % 4:
        data += b'\x00\x00'
    header = struct.pack('<HHIIIIII', 0x0001, 28, 28 + 4 * len(offsets) + len(data),
                         len(offsets), 0, 0, 28 + 4 * len(offsets), 0)
    body = b''.join(struct.pack('<I', o) for o in offsets) + data
    return header + body

def start_ns(prefix, uri):
    return chunk(0x0100, 16, struct.pack('<iiii', -1, 2, prefix, uri))

def end_ns(prefix, uri):
    return chunk(0x0101, 16, struct.pack('<iiii', -1, 2, prefix, uri))

def attr(name_idx, value_type, value, raw=-1, ns=-1):
    tv = struct.pack('<HBB', 8, 0, value_type) + struct.pack('<I', value)
    return struct.pack('<iii', ns, name_idx, raw) + tv

def start_element(name, attrs=(), line=2):
    # node: comment, line | attrExt: ns, name, attrStart, attrSize, attrCount, id, class, style
    payload = struct.pack('<ii', -1, line)
    payload += struct.pack('<iiHHHHHH', -1, name, 20, 20, len(attrs), 0, 0, 0)
    payload += b''.join(attrs)
    return chunk(0x0102, 16, payload)

def end_element(name, line=2):
    return chunk(0x0103, 16, struct.pack('<iiii', -1, line, -1, name))

def resource_map(ids):
    return chunk(0x0180, 8, b''.join(struct.pack('<I', i) for i in ids))

ATTR_RESID = {
    'label': 0x01010001,
    'name': 0x01010003,
    'exported': 0x01010010,
    'minSdkVersion': 0x0101020c,
    'targetSdkVersion': 0x01010270,
    'versionCode': 0x0101021b,
    'versionName': 0x0101021c,
}
ATTR_IDX = {k: add_str(k) for k in ATTR_RESID}

NS_URI = add_str('http://schemas.android.com/apk/res/android')
NS_PRE = add_str('android')

def a_name(v): return attr(ATTR_IDX['name'], 0x03, add_str(v), add_str(v), NS_URI)
def a_label(v): return attr(ATTR_IDX['label'], 0x03, add_str(v), add_str(v), NS_URI)
def a_exported(v): return attr(ATTR_IDX['exported'], 0x12, 1 if v else 0, ns=NS_URI)
def a_min(v): return attr(ATTR_IDX['minSdkVersion'], 0x10, v, ns=NS_URI)
def a_target(v): return attr(ATTR_IDX['targetSdkVersion'], 0x10, v, ns=NS_URI)
def a_vercode(v): return attr(ATTR_IDX['versionCode'], 0x10, v, ns=NS_URI)
def a_vername(v): return attr(ATTR_IDX['versionName'], 0x03, add_str(v), add_str(v), NS_URI)
def a_package(v): return attr(add_str('package'), 0x03, add_str(v), add_str(v))

def build_xml():
    m = b''
    m += start_ns(NS_PRE, NS_URI)
    m += start_element(add_str('manifest'), [
        a_package('com.umd.helper'), a_vercode(1), a_vername('1')])
    m += start_element(add_str('uses-sdk'), [a_min(26), a_target(33)])
    m += end_element(add_str('uses-sdk'))
    m += start_element(add_str('uses-permission'), [a_name('com.termux.permission.RUN_COMMAND')])
    m += end_element(add_str('uses-permission'))
    m += start_element(add_str('application'), [a_label('umd helper')])
    m += start_element(add_str('activity'), [a_name('.MainActivity'), a_exported(True)])
    m += start_element(add_str('intent-filter'))
    m += start_element(add_str('action'), [a_name('android.intent.action.MAIN')])
    m += end_element(add_str('action'))
    m += start_element(add_str('category'), [a_name('android.intent.category.LAUNCHER')])
    m += end_element(add_str('category'))
    m += end_element(add_str('intent-filter'))
    m += end_element(add_str('activity'))
    m += end_element(add_str('application'))
    m += end_element(add_str('manifest'))
    m += end_ns(NS_PRE, NS_URI)
    rmap_ids = [ATTR_RESID[k] for k in ATTR_RESID]
    return chunk(0x0003, 8, string_pool() + resource_map(rmap_ids) + m)

def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
    os.makedirs(out, exist_ok=True)
    xml = build_xml()
    open(os.path.join(out, 'AndroidManifest.xml'), 'wb').write(xml)
    apk = zipfile.ZipFile(os.path.join(out, 'unsigned.apk'), 'w', zipfile.ZIP_DEFLATED)
    apk.writestr('AndroidManifest.xml', xml)
    apk.writestr('classes.dex', open(os.path.join(out, 'classes.dex'), 'rb').read())
    apk.close()
    print('APK assembled:', os.path.getsize(os.path.join(out, 'unsigned.apk')), 'bytes')

main()