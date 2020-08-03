when defined(profiler):
  import nimprof

import
  imageman,
  gb/dmg, shell/render


const
  BootRom = ""
  Rom = staticRead("../123/gb-test-roms-master/cpu_instrs/cpu_instrs.gb")

proc init(): Gameboy =
  result = newGameboy(BootRom)
  result.load(Rom)

proc frame(dmg: Gameboy, isRunning: var bool): Image[ColorRGBU] =
  try:
    var
      needsRedraw = false
    while not needsRedraw:
      needsRedraw = needsRedraw or dmg.step()
  except:
    isRunning = false

  result = initPainter(PaletteDefault).renderLcd(dmg.ppu)



when defined(wasm):
  include shell/simple/wasm
elif defined(psp):
  include shell/simple/psp
else:
  include shell/simple/pc

main()
