when defined(profiler):
  import nimprof

import
  gb/dmg/[dmg, cpu], shell/render



const
  BootRom = ""
  Rom = staticRead("../123/Super Mario Land 2 - 6 Golden Coins (USA, Europe) (Rev B).gb")



var
  gameboy = newGameboy(BootRom)
  isRunning = true
gameboy.load(Rom)

while isRunning:
  var
    needsRedraw = false
  while not needsRedraw and isRunning:
    needsRedraw = needsRedraw or gameboy.step()
    if gameboy.cpu.state.pc == 0x06f1:
      isRunning = false

  discard initPainter(PaletteDefault).renderLcd(gameboy.ppu)

  if gameboy.cycles >= 733894900:
    isRunning = false
