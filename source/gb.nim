##[

  Gameboy models:
    DMG   Game Boy
    MGB   Game Boy Pocket
    SGB   Super Game Boy
    SGB2  Super Game Boy 2
    CGB   Game Boy Color

]##
import
  gb/[mem, cpu, timer, display, cartridge, joypad]



type
  BootRom = ref object
    data: string

proc pushHandler(mcu: Mcu, self: BootRom) =
  let
    bootRomHandler = MemHandler(
      read: proc(address: MemAddress): uint8 = cast[uint8](self.data[address.int]),
      write: proc(address: MemAddress, value: uint8) = discard,
      area: 0.MemAddress ..< 256.MemAddress
    )
    bootRomDisableHandler = MemHandler(
      read: proc(address: MemAddress): uint8 = 0,
      write: proc(address: MemAddress, value: uint8) =
        mcu.popHandler()
        mcu.popHandler()
      ,
      area: 0xff50.MemAddress .. 0xff50.MemAddress
    )
  mcu.pushHandler(bootRomHandler)
  mcu.pushHandler(bootRomDisableHandler)

proc newBootRom(file: string): BootRom =
  result = BootRom(
    data: readFile(file)
  )
  assert result.data.len == 256


type
  Gameboy* = ref object
    mcu*: Mcu
    cpu*: Cpu
    timer*: Timer
    display*: Display
    joypad*: Joypad

    boot: BootRom
    cart*: Cartridge
    bootRom*: string
    testMemory*: seq[uint8]

proc load*(self: Gameboy, rom: string) =
  self.testMemory = newSeq[uint8](uint16.high.int + 1)

  self.cart = initCartridge(rom)

  self.mcu.clearHandlers()
  self.mcu.pushHandler(0, addr self.testMemory)
  self.mcu.pushHandler(self.cpu)
  self.mcu.pushHandler(self.timer)
  self.mcu.pushHandler(self.display)
  self.mcu.pushHandler(self.joypad)
  
  self.mcu.pushHandlers(self.cart)
  self.mcu.pushHandler(self.boot)

proc newGameboy*(bootRom: string): Gameboy =
  let
    mcu = newMcu()
  result = Gameboy(
    mcu: mcu,
    cpu: newCpu(mcu),
    timer: newTimer(mcu),
    display: newDisplay(mcu),
    joypad: newJoypad(mcu),
    boot: newBootRom(bootRom)
  )
