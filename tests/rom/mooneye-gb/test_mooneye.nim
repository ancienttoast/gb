##[

Source: <https://github.com/mattcurrie/dmg-acid2>

]##
import
  std/unittest,
  nimPNG, imageman,
  gb/gameboy, gb/dmg/dmg, shell/render



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

proc checkLcd(expected: string, result: Image[ColorRGBU]) =
  let
    expectedPng = decodePNG24(readFile(expected))
  check result.width == expectedPng.width
  check result.height == expectedPng.height
  check equalMem(unsafeAddr result.data[0], unsafeAddr expectedPng.data[0], result.width * result.height * 3)


suite "rom.mooneye-gb.emulator-only.mbc1":
  test "bits_bank1":
    var
      gameboy = newGameboy(readFile("tests/rom/mooneye-gb/emulator-only/mbc1/bits_bank1.gb"))
    check gameboy.kind == gkDMG

    while gameboy.dmg.cpu.state.pc != 0x486d:
      discard gameboy.step()

    let
      result = initPainter(PaletteBlackAndWhite).renderLcd(gameboy.dmg.ppu)
    checkLcd("tests/rom/mooneye-gb/expected.emulator-only.mbc1.bits_bank1.png", result)

suite "rom.mooneye-gb.manual-only":
  test "sprite_priority":
    skip
    #[
    var
      gameboy = newGameboy(readFile("tests/rom/mooneye-gb/manual-only/sprite_priority.gb"))
    check gameboy.kind == gkDMG

    while gameboy.dmg.cpu.state.pc != 0x0198:
      discard gameboy.step()

    let
      result = initPainter(PaletteBlackAndWhite).renderLcd(gameboy.dmg.ppu)
    checkLcd("tests/rom/mooneye-gb/expected_sprite_priority.png", result)
    ]#
