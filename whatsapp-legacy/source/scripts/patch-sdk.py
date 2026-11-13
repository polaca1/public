# Repair two incomplete link stubs in the pinned community SDK, no runtime shim.
from pathlib import Path
import sys
root=Path(sys.argv[1])
p=root/'usr/lib/libSystem.tbd'
p.write_text(p.read_text().replace('/usr/lib/system/liblaunch.dylib, ',''))
p=root/'usr/lib/system/libsystem_c.tbd'
p.write_text(p.read_text().replace('symbols:            [','symbols:            [ _memset, _memchr, _memcmp, _memcpy, _memmove, _strcmp,',1))
