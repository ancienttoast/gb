import
  mem, cpu



type
  BootRom* = ref object
    data: string

proc setupMemHandler*(mcu: Mcu, self: BootRom) =
  if self.data == "":
    return

  let
    bootRomHandler = MemHandler(
      read: proc(address: MemAddress): uint8 = cast[uint8](self.data[address.int]),
      write: proc(address: MemAddress, value: uint8) = discard
    )
    bootRomDisableHandler = MemHandler(
      read: proc(address: MemAddress): uint8 = 0,
      write: proc(address: MemAddress, value: uint8) =
        mcu.clearHandler(msBootRom)
    )
  mcu.setHandler(msBootRom, bootRomHandler)
  mcu.setHandler(msBootRomFlag, bootRomDisableHandler)

func hasRom*(self: BootRom): bool =
  self.data.len > 0

proc newBootRom*(bootRom: string): BootRom =
  assert bootRom.len == 256 or bootRom.len == 0
  result = BootRom(
    data: bootRom
  )



proc staticBoot*(cpu: Cpu, mcu: Mcu) =
  cpu.state[rAF] = 0x01b0
  cpu.state[rBC] = 0x0013
  cpu.state[rDE] = 0x00d8
  cpu.state[rHL] = 0x014d
  cpu.state.sp = 0xfffe
  cpu.state.pc = 0x0100

  mcu[0xff05] = 0x00'u8   # TIMA
  mcu[0xff06] = 0x00'u8   # TMA
  mcu[0xff07] = 0x00'u8   # TAC
  mcu[0xff10] = 0x80'u8   # NR10
  mcu[0xff11] = 0xbf'u8   # NR11
  mcu[0xff12] = 0xf3'u8   # NR12
  mcu[0xff14] = 0xbf'u8   # NR14
  mcu[0xff16] = 0x3f'u8   # NR21
  mcu[0xff17] = 0x00'u8   # NR22
  mcu[0xff19] = 0xbf'u8   # NR24
  mcu[0xff1A] = 0x7f'u8   # NR30
  mcu[0xff1b] = 0xff'u8   # NR31
  mcu[0xff1c] = 0x9f'u8   # NR32
  mcu[0xff1e] = 0xbf'u8   # NR33
  mcu[0xff20] = 0xff'u8   # NR41
  mcu[0xff21] = 0x00'u8   # NR42
  mcu[0xff22] = 0x00'u8   # NR43
  mcu[0xff23] = 0xbf'u8   # NR44
  mcu[0xff24] = 0x77'u8   # NR50
  mcu[0xff25] = 0xf3'u8   # NR51
  mcu[0xff26] = 0xf1'u8   # NR52
  mcu[0xff40] = 0x91'u8   # LCDC
  mcu[0xff42] = 0x00'u8   # SCY
  mcu[0xff43] = 0x00'u8   # SCX
  mcu[0xff45] = 0x00'u8   # LYC
  mcu[0xff47] = 0xfc'u8   # BGP
  mcu[0xff48] = 0xff'u8   # OBP0
  mcu[0xff49] = 0xff'u8   # OBP1
  mcu[0xff4A] = 0x00'u8   # WY
  mcu[0xff4b] = 0x00'u8   # WX
  mcu[0xffff] = 0x00'u8   # IE