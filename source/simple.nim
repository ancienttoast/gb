when defined(profiler):
  import nimprof

import
  imageman,
  gb/gameboy, shell/render


const
  Rom = staticRead("../tests/rom/blargg/cpu_instrs/cpu_instrs.gb")

proc init(): Gameboy =
  result = newGameboy(Rom)

proc frame(gameboy: Gameboy, isRunning: var bool): Image[ColorRGBU] =
  try:
    discard gameboy.frame(0)
  except:
    isRunning = false

  result = initPainter(PaletteDefault).renderLcd(gameboy.dmg.ppu)



when defined(wasm):
  include shell/simple/wasm
elif defined(psp):
  include shell/simple/psp
else:
  include shell/simple/pc

main()
