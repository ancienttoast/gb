##[

Source: <https://github.com/mattcurrie/dmg-acid2>

]##
import
  std/unittest,
  nimPNG, imageman,
  gb/gameboy, gb/dmg/dmg, shell/render



proc checkLcd(expected: string, result: Image[ColorRGBU]) =
  let
    expectedPng = decodePNG24(readFile(expected))
  check result.width == expectedPng.width
  check result.height == expectedPng.height
  check equalMem(unsafeAddr result.data[0], unsafeAddr expectedPng.data[0], result.width * result.height * 3)

suite "rom.dmg-acid2":
  test "dmg-acid2":
    var
      gameboy = newGameboy("")
    gameboy.load(readFile("tests/rom/dmg_acid2/dmg-acid2.gb"))
    check gameboy.kind == gkDMG

    while gameboy.dmg.cycles < 4424398:
      discard gameboy.step()

    let
      result = initPainter(PaletteBlackAndWhite).renderLcd(gameboy.dmg.ppu)
    checkLcd("tests/rom/dmg_acid2/reference-dmg.png", result)
