when defined(profiler):
  import nimprof

import
  gb/[dmg, cpu, ppu]



const
  BootRom = ""
  Rom = staticRead("../123/gb-test-roms-master/cpu_instrs/cpu_instrs.gb")



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

  discard gameboy.ppu.renderLcd()
