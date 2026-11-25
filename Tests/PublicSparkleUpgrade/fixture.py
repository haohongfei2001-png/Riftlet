"""Build the fixture tool from the exact stable build 65 Core and SQLite module."""
from pathlib import Path
import json,shutil,subprocess,tempfile,sys
def build(repository, base):
    pinned={'RiftletCore':'77d15fc1965bc05c15834b9d643ea1672b1f9162','CSQLite':'b09e2c80f8ca3beaacb84be61d257db6e3ce97b5'}
    package=base/'fixture-source'
    src=package/'Sources';src.mkdir(parents=True)
    for name,tree in pinned.items():
        actual=subprocess.check_output(['git','-C',repository,'rev-parse','HEAD:Sources/'+name],text=True).strip()
        assert actual==tree
        assert not subprocess.check_output(['git','-C',repository,'status','--porcelain','--','Sources/'+name]).strip()
        shutil.copytree(repository/'Sources'/name,src/name)
    entry=src/'SeedOperation';entry.mkdir()
    shutil.copy2(Path(__file__).with_name('SeedOperation.swift'),entry/'SeedOperation.swift')
    (package/'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"UpgradeFixture",platforms:[.macOS(.v13)],targets:[
    .systemLibrary(name:"CSQLite",pkgConfig:"sqlite3"),.target(name:"RiftletCore",dependencies:["CSQLite"]),
    .executableTarget(name:"SeedOperation",dependencies:["RiftletCore"])])
''')
    cmd=['swift','build','--package-path',str(package),'--product','SeedOperation','-j','3']
    subprocess.run(cmd,check=True,timeout=190)
    directory=Path(subprocess.check_output(cmd+['--show-bin-path'],text=True).strip())
    return directory/'SeedOperation'
if __name__=='__main__':
    print(build(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve()))
