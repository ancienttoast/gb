import
  std/[unittest, strformat, os],
  nimPNG, imageman,
  gb/gameboy, gb/dmg/[dmg, cpu], shell/render



proc checkLcd(expected: string, result: Image[ColorRGBU]) =
  let
    expectedPng = decodePNG24(readFile(expected))
  check result.width == expectedPng.width
  check result.height == expectedPng.height
  check equalMem(unsafeAddr result.data[0], unsafeAddr expectedPng.data[0], result.width * result.height * 3)

#[
proc saveResult(file: string, result: Image[ColorRGBU]) =
  var
    buffer = newStringOfCap(result.width * result.height * 3)
  for d in result.data:
    buffer &= d[0].char
    buffer &= d[1].char
    buffer &= d[2].char
  discard savePNG24(file, buffer, result.width, result.height)
]#


template testFull(name: string, rom: string, expected: string, stop: int) =
  test name:
    var
      gameboy = newGameboy("")
    gameboy.load(readFile("tests/rom/" & rom))
    check gameboy.kind == gkDMG

    while gameboy.dmg.cpu.state.pc != stop:
      discard gameboy.step()

    let
      result = initPainter(PaletteDefault).renderLcd(gameboy.dmg.ppu)
    checkLcd("tests/rom/blargg/" & expected, result)

template testCpu(file: string, stop: int) =
  let
    name = splitFile(file).name
  testFull("cpu_instrs - " & name, "blargg/cpu_instrs/" & file, "result_cpu_instrs_" & name & ".png", stop)


suite "Blargg test roms":
  testCpu "individual/01-special.gb", 0xc7d2
  testCpu "individual/02-interrupts.gb", 0xc7f4
  testCpu "individual/03-op sp,hl.gb", 0xcb44
  testCpu "individual/04-op r,imm.gb", 0xcb35
  testCpu "individual/05-op rp.gb", 0xcb31
  testCpu "individual/06-ld r,r.gb", 0xcc5f
  testCpu "individual/07-jr,jp,call,ret,rst.gb", 0xcbb0
  testCpu "individual/08-misc instrs.gb", 0xcb91
  testCpu "individual/09-op r,r.gb", 0xce67
  testCpu "individual/10-bit ops.gb", 0xcf58
  testCpu "individual/11-op a,(hl).gb", 0xcc62
  testFull "cpu_instrs", "blargg/cpu_instrs/cpu_instrs.gb", "result_cpu_instrs.png", 0x06f1
  testFull "instr_timing", "blargg/instr_timing/instr_timing.gb", "result_instr_timing.png", 0xc8b0