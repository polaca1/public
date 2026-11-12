import pathlib,struct,subprocess,sys,tempfile,plistlib
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(['dpkg-deb','-x',sys.argv[1],tmp],check=True)
    app=pathlib.Path(tmp)/'Applications/WhatsAppLegacy.app'
    binary=(app/'WhatsAppLegacy').read_bytes()
    magic,cpu,subtype,kind,ncmds,size,flags=struct.unpack_from('<7I',binary)
    assert magic==0xfeedface and cpu==12 and subtype & 0xffffff==9 and kind==2,'Expected 32-bit ARMv7 executable'
    offset=28; version=None; signed=False; dependencies=[]
    for _ in range(ncmds):
        cmd,length=struct.unpack_from('<II',binary,offset)
        assert length>=8 and offset+length<=len(binary)
        if cmd==0x25: version=struct.unpack_from('<I',binary,offset+8)[0]
        if cmd==0x1d: signed=True
        if cmd==0xc:
            name=struct.unpack_from('<I',binary,offset+8)[0]
            dependencies.append(binary[offset+name:offset+length].split(b'\0')[0].decode())
        offset+=length
    assert version==0x000a0000 and signed
    assert all(d.startswith(('/System/Library/','/usr/lib/')) for d in dependencies)
    assert plistlib.loads((app/'Info.plist').read_bytes())['MinimumOSVersion']=='10.0'
    print('PASS: ARMv7 32-bit, iOS 10.0 target, signature command, system-only dylibs. Device execution NOT tested.')
