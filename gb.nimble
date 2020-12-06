# Package
version       = "0.0.1"
author        = "stilll"
description   = "Gameboy emulator"
license       = "MIT"
srcDir        = "source"
backend       = "cpp"
bin           = @["debugger", "simple"]



# Dependencies
requires "nim >= 1.0.4", "sdl2 >= 2.0", "nimgl >= 1.1.1", "imageman >= 0.6.5", "opengl >= 1.1.0", "bingod >= 0.0.1"
requires "nimPNG >= 0.3.1"





const
  appName = "GB"


import
  strformat, os


task wasm, "wasm":
  const
    build = "build/wasm"
  cpDir("dist/wasm", build)
  let
    file = system.paramStr(system.paramCount())
    (_, name, _) = splitFile(file)
  exec &"nim --out:{build}/gb.html --define:release --define:wasm --passL:\"--shell-file {build}/gb.html\" c {file}"

task psp, "psp":
  const
    build = "build/psp"
  cpDir("dist/psp", build)
  let
    sdk = getEnv("PSPSDK") & "/bin/"
    file = system.paramStr(system.paramCount())
    (_, name, _) = splitFile(file)
  exec &"nim --define:release --define:psp --define:psp_user --define:bsd --out:{build}/{name}.elf c {file}"
  withDir build:
    exec sdk & &"mksfoex -d MEMSIZE=1 '{appName}' PARAM.SFO"
    exec sdk & &"psp-fixup-imports {name}.elf"
    exec sdk & &"psp-strip {name}.elf -o {name}_strip.elf"
    exec sdk & &"pack-pbp EBOOT.PBP PARAM.SFO ICON.PNG ICON1.PNG UNKPNG.PNG PIC1.PNG NULL {name}_strip.elf NULL"

    rmFile &"{name}.elf"
    rmFile &"{name}_strip.elf"

task test, "Run the test suite":
  var
    tests = "unit*::"
  if system.paramStr(system.paramCount()) != "test":
    tests = system.paramStr(system.paramCount())
  exec &"nim --run c tests/test.nim \"{tests}\""
