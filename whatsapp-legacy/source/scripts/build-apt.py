"""Build flat APT indexes; does not sign or publish. Pass the directory containing debs/."""
import datetime,gzip,hashlib,pathlib,subprocess,sys
p=pathlib.Path(sys.argv[1]).resolve()
index=subprocess.check_output(['dpkg-scanpackages','debs','/dev/null'],cwd=p)
(p/'Packages').write_bytes(index)
(p/'Packages.gz').write_bytes(gzip.compress(index,mtime=0))
release='Origin: WhatsApp Legacy Experimental\nLabel: WhatsApp Legacy Experimental\nSuite: stable\nCodename: legacy\nArchitectures: iphoneos-arm\nDescription: Native text messaging implementation; physical iPhone verification pending.\nDate: '+datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')+'\nSHA256:\n'
for name in ['Packages','Packages.gz']:
 b=(p/name).read_bytes();release+=f' {hashlib.sha256(b).hexdigest()} {len(b)} {name}\n'
(p/'Release').write_text(release)
