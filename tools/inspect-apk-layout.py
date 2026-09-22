"""解剖两个 APK 的内部布局，找出"文件大小 - 条目数据"的那段空隙到底在哪。

起因：0.1.2 与 0.1.3 的条目内容只差 24 KB，可文件大小差了 1.02 MB —— 不解释清楚不放心。
"""
import struct
import sys
import zipfile

EOCD = b"PK\x05\x06"
SIG_BLOCK = b"APK Sig Block 42"


def analyze(path: str) -> None:
    with open(path, "rb") as fh:
        blob = fh.read()
    size = len(blob)

    # 从尾部找 EOCD（注释最长 65535）
    tail = blob.rfind(EOCD, max(0, size - 65557))
    if tail < 0:
        print(f"{path}: 找不到 EOCD")
        return
    cd_size, cd_off = struct.unpack("<II", blob[tail + 12:tail + 20])
    comment_len = struct.unpack("<H", blob[tail + 20:tail + 22])[0]

    # APK 签名块紧挨在中央目录之前
    sig_size = 0
    sig_pos = blob.rfind(SIG_BLOCK, 0, cd_off)
    if sig_pos > 0:
        block_len = struct.unpack("<Q", blob[sig_pos - 16:sig_pos - 8])[0]
        sig_size = block_len + 8

    with zipfile.ZipFile(path) as zf:
        data = sum(i.compress_size for i in zf.infolist())
        entries = len(zf.infolist())

    print(f"{path}")
    print(f"  文件大小        {size:,}")
    print(f"  条目压缩后合计  {data:,}   （{entries} 个条目）")
    print(f"  中央目录        {cd_size:,} @ {cd_off:,}")
    print(f"  签名块          {sig_size:,}")
    print(f"  尾部注释        {comment_len:,}")
    print(f"  中央目录后剩余  {size - tail - 22 - comment_len:,}  （正常应为 0）")
    overhead = size - data
    print(f"  数据之外的开销  {overhead:,}  （本地头 + 目录 + 签名块 + 对齐填充）")
    # 本地文件头 + 对齐填充 = 开销 - 目录 - 签名块
    print(f"  其中「头+填充」 {overhead - cd_size - sig_size:,}")
    report_padding(blob, path)


def report_padding(blob: bytes, path: str) -> None:
    """逐个条目算"本条目数据之后到下一个本地头之间"的填充，找出谁被对齐了。"""
    import collections

    with zipfile.ZipFile(path) as zf:
        infos = sorted(zf.infolist(), key=lambda i: i.header_offset)
    holes = []
    for idx, info in enumerate(infos):
        name_len, extra_len = struct.unpack("<HH", blob[info.header_offset + 26:info.header_offset + 30])
        data_end = info.header_offset + 30 + name_len + extra_len + info.compress_size
        next_start = infos[idx + 1].header_offset if idx + 1 < len(infos) else len(blob)
        gap = next_start - data_end
        if gap > 0:
            holes.append((gap, info.filename))
    holes.sort(reverse=True)
    total = sum(g for g, _ in holes)
    print(f"  有填充的条目    {len(holes)} 个，合计 {total:,} 字节；最大的 5 个：")
    for gap, name in holes[:5]:
        print(f"      {gap:>6,}  {name}")
    groups = collections.Counter(name.rsplit('/', 1)[0] if '/' in name else name for _, name in holes)
    print(f"  按目录归类：{dict(groups.most_common(5))}")



for p in sys.argv[1:]:
    analyze(p)
