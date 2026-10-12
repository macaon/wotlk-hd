"""Read files from the WotLK client's MPQ chain through StormLib (ctypes)."""
import ctypes
import os

STORM = os.environ.get("STORMLIB", os.path.expanduser("~/Git/ref/StormLib/build/libstorm.so"))
WOW = os.environ.get("WOW_DIR", os.path.expanduser("~/Games/wotlk"))

# Highest priority first: later patches override earlier archives.
CHAIN = [
    "enUS/patch-enUS-3.MPQ", "enUS/patch-enUS-2.MPQ", "enUS/patch-enUS.MPQ",
    "patch-3.MPQ", "patch-2.MPQ", "patch.MPQ",
    "enUS/lichking-locale-enUS.MPQ", "enUS/expansion-locale-enUS.MPQ", "enUS/locale-enUS.MPQ",
    "lichking.MPQ", "expansion.MPQ", "common-2.MPQ", "common.MPQ",
]

_s = ctypes.CDLL(STORM)
_h = ctypes.c_void_p
_s.SFileOpenArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(_h)]
_s.SFileOpenFileEx.argtypes = [_h, ctypes.c_char_p, ctypes.c_uint, ctypes.POINTER(_h)]
_s.SFileGetFileSize.argtypes = [_h, ctypes.POINTER(ctypes.c_uint)]
_s.SFileGetFileSize.restype = ctypes.c_uint
_s.SFileReadFile.argtypes = [_h, ctypes.c_void_p, ctypes.c_uint, ctypes.POINTER(ctypes.c_uint), ctypes.c_void_p]
_s.SFileCloseFile.argtypes = [_h]

_s.SFileCreateArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(_h)]
_s.SFileCreateFile.argtypes = [_h, ctypes.c_char_p, ctypes.c_ulonglong, ctypes.c_uint, ctypes.c_uint,
                               ctypes.c_uint, ctypes.POINTER(_h)]
_s.SFileWriteFile.argtypes = [_h, ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint]
_s.SFileFinishFile.argtypes = [_h]
_s.SFileCloseArchive.argtypes = [_h]

STREAM_FLAG_READ_ONLY = 0x100
MPQ_CREATE_LISTFILE = 0x00100000
MPQ_CREATE_ATTRIBUTES = 0x00200000
MPQ_FILE_COMPRESS = 0x200
MPQ_FILE_REPLACEEXISTING = 0x80000000
MPQ_COMPRESSION_ZLIB = 0x02


def write_archive(path, files):
    """Create a version 1 MPQ (what 3.3.5 patches are) holding {archived name: bytes}."""
    if os.path.exists(path):
        os.remove(path)
    h = _h()
    n = max(len(files) + 16, 64)
    if not _s.SFileCreateArchive(path.encode(), MPQ_CREATE_LISTFILE | MPQ_CREATE_ATTRIBUTES, n, ctypes.byref(h)):
        raise OSError(f"cannot create {path}")
    try:
        for name, data in files.items():
            data = data() if callable(data) else data  # built on demand (chars.py's textures)
            f = _h()
            if not _s.SFileCreateFile(h, name.encode(), 0, len(data), 0,
                                      MPQ_FILE_COMPRESS | MPQ_FILE_REPLACEEXISTING, ctypes.byref(f)):
                raise OSError(f"cannot add {name}")
            ok = _s.SFileWriteFile(f, data, len(data), MPQ_COMPRESSION_ZLIB)
            if not _s.SFileFinishFile(f) or not ok:
                raise OSError(f"cannot write {name}")
    finally:
        _s.SFileCloseArchive(h)


class Client:
    def __init__(self, wow_dir=WOW, chain=CHAIN):
        self.archives = []
        for name in chain:
            path = os.path.join(wow_dir, "Data", name)
            if not os.path.exists(path):
                continue
            h = _h()
            if not _s.SFileOpenArchive(path.encode(), 0, STREAM_FLAG_READ_ONLY, ctypes.byref(h)):
                raise OSError(f"cannot open {path}")
            self.archives.append((name, h))

    def read(self, path):
        """The file's bytes from the highest-priority archive that has it, or None."""
        for _, a in self.archives:
            f = _h()
            if not _s.SFileOpenFileEx(a, path.encode(), 0, ctypes.byref(f)):
                continue
            try:
                size = _s.SFileGetFileSize(f, None)
                buf = ctypes.create_string_buffer(size)
                got = ctypes.c_uint()
                if not _s.SFileReadFile(f, buf, size, ctypes.byref(got), None) or got.value != size:
                    raise OSError(f"short read of {path}")
                return buf.raw
            finally:
                _s.SFileCloseFile(f)
        return None


if __name__ == "__main__":
    c = Client()
    d = c.read("DBFilesClient\\CreatureDisplayInfo.dbc")
    assert d and d[:4] == b"WDBC", "CreatureDisplayInfo.dbc not found"
    print(len(c.archives), "archives; CreatureDisplayInfo.dbc", len(d), "bytes")
    import tempfile
    with tempfile.TemporaryDirectory() as t:
        os.mkdir(os.path.join(t, "Data"))
        write_archive(os.path.join(t, "Data", "test.MPQ"), {"Dir\\A.txt": b"hello"})
        assert Client(t, ["test.MPQ"]).read("dir\\a.txt") == b"hello", "MPQ round trip failed"
    print("MPQ write/read round trip ok")
