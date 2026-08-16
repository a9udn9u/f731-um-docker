#!/usr/bin/env python3
import zipfile, struct, sys

def decode_manifest(path):
    if path.endswith('.apk'):
        z = zipfile.ZipFile(path)
        data = z.read('AndroidManifest.xml')
    else:
        data = open(path, 'rb').read()
    out = []
    # string pool
    ctype, hsize, size = struct.unpack_from('<HHI', data, 8)
    pt, ph, ps, count, style, flags, sstart, sstyles = struct.unpack_from('<HHIIIIII', data, 8)
    off = [struct.unpack_from('<I', data, 8+ph+4*i)[0] for i in range(count)]
    def getstr(i):
        if i < 0 or i >= count: return '<OOB:%d>' % i
        at = 8 + sstart + off[i]
        ln = struct.unpack_from('<H', data, at)[0]
        return data[at+2:at+2+ln*2].decode('utf-16-le')
    # resource map
    pos = 8 + size
    rmap = []
    while pos < len(data):
        ctype, hsize, size = struct.unpack_from('<HHI', data, pos)
        if ctype == 0x0180:
            n = (size - 8) // 4
            rmap = list(struct.unpack_from('<%dI' % n, data, pos+8))
            break
        pos += size
    # walk
    pos = 8 + (size if False else struct.unpack_from('<I', data, 12)[0])
    pos = 8 + struct.unpack_from('<I', data, 12)[0]
    while pos < len(data):
        ctype, hsize, size = struct.unpack_from('<HHI', data, pos)
        if ctype == 0x0102:
            line, comment = struct.unpack_from('<ii', data, pos+8)
            ns, name = struct.unpack_from('<ii', data, pos+16)
            astart, asize, acount = struct.unpack_from('<HHH', data, pos+24)
            ename = getstr(name)
            out.append('<%s ns=%s>' % (ename, getstr(ns) if ns >= 0 else 'null'))
            for i in range(acount):
                a = data[pos+16+astart+i*asize : pos+16+astart+(i+1)*asize]
                ans, aname, araw = struct.unpack_from('<iii', a, 0)
                tsize, res0, atype = struct.unpack_from('<HBB', a, 12)
                aval = struct.unpack_from('<I', a, 16)[0]
                ns_s = getstr(ans) if ans >= 0 else ''
                if aname >= 0 and aname < len(rmap):
                    name_s = 'id:%#x' % rmap[aname]
                else:
                    name_s = getstr(aname)
                if atype == 0x03:
                    val_s = repr(getstr(aval))
                elif atype == 0x10:
                    val_s = str(aval)
                elif atype == 0x12:
                    val_s = str(bool(aval))
                else:
                    val_s = 'type%#x:%d' % (atype, aval)
                out.append('    %s%s=%s' % (ns_s + ':' if ns_s else '', name_s, val_s))
        elif ctype == 0x0103:
            ns, name = struct.unpack_from('<ii', data, pos+16)
            out.append('</%s>' % getstr(name))
        pos += size
    return out

for p in sys.argv[1:]:
    print('==== %s ====' % p)
    for line in decode_manifest(p):
        print(line)