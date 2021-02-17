import
  boot, mem, cpu, apu, timer, ppu, mbc, joypad



let
  FFHandler* = MemHandler(
    read: proc(address: MemAddress): uint8 = 0xff,
    write: proc(address: MemAddress, value: uint8) = discard
  )


type
  DmgState* = tuple
    testMemory: seq[uint8]
    cpu: CpuState
    timer: TimerState
    ppu: PpuState
    apu: ApuState
    joypad: JoypadState
    cart: MbcState


  Dmg* = ref object
    mcu*: Mcu
    cpu*: Cpu
    timer*: Timer
    ppu*: Ppu
    apu*: Apu
    joypad*: Joypad
    cart*: Cartridge

    boot: BootRom
    bootRom*: string
    testMemory*: seq[uint8]
    cycles*: uint64

proc reset*(self: Dmg, rom: string) =
  self.testMemory = newSeq[uint8](uint16.high.int + 1)

  self.mcu.clearHandlers()
  self.mcu.setHandler(msDebug, addr self.testMemory)
  self.mcu.setupMemHandler(self.cpu)
  self.mcu.setupMemHandler(self.timer)
  self.mcu.setupMemHandler(self.ppu)
  self.mcu.setupMemHandler(self.apu)
  self.mcu.setupMemHandler(self.joypad)
  
  self.mcu.setupMemHandler(self.boot)
  if rom != "":
    self.cart = initCartridge(rom)
    self.mcu.setupMemHandler(self.cart)
  if not self.boot.hasRom():
    staticBoot(self.cpu, self.mcu)
  
  # TODO: bgb does this, but I wasn't able to find any documentation about this
  self.mcu.setHandler(msCgbSwitch, FFHandler)
  self.mcu.setHandler(msCgbVRamBank, FFHandler)
  self.mcu.setHandler(msCgbVramDma, FFHandler)
  self.mcu.setHandler(msCgbInfra, FFHandler)
  
  self.cycles = 0

proc reset*(self: Dmg) =
  self.reset(self.cart.data)

proc step*(self: Dmg): bool =
  let
    cycles = self.cpu.step(self.mcu) * 4
  if sfStopped notin self.cpu.state.status:
    self.cart.step(cycles)
    self.timer.step(cycles)
    self.apu.step(cycles)
    result = self.ppu.step(cycles)
  else:
    result = true
  self.cycles += cycles.uint64


proc save*(self: Dmg): DmgState =
  result.testMemory = self.testMemory
  result.cpu = self.cpu.state
  result.timer = self.timer.state
  result.ppu = self.ppu.state
  result.apu = self.apu.state
  result.joypad = self.joypad.state
  result.cart = self.cart.state

proc load*(self: Dmg, state: DmgState) =
  self.testMemory = state.testMemory
  self.cpu.state = state.cpu
  self.timer.state = state.timer
  self.ppu.state = state.ppu
  self.apu.state = state.apu
  self.joypad.state = state.joypad
  self.cart.state = state.cart


proc newDmg*(bootRom = ""): Dmg =
  let
    mcu = newMcu()
  Dmg(
    mcu: mcu,
    cpu: newCpu(mcu),
    timer: newTimer(mcu),
    ppu: newPpu(mcu),
    apu: newApu(mcu),
    joypad: newJoypad(mcu),
    boot: newBootRom(bootRom),
    cycles: 0
  )
