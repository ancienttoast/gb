import
  gb/dmg/[mem, cpu]
import gb/dmg/boot as dmg_boot

export dmg_boot.BootRom, dmg_boot.setupMemHandler, dmg_boot.newBootRom, dmg_boot.hasRom



proc staticBoot*(cpu: Cpu, mcu: Mcu) =
  dmg_boot.staticBoot(cpu, mcu)
  cpu.state[rAF] = 0x11b0