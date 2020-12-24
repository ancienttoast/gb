##[

Differences

  VRAM has 2 banks now

  0xff40  lcdc - The main LCD control register.
    bit 0 - BG and Window Master Priority
            When Bit 0 is cleared, the background and window lose their priority - the sprites will be
            always displayed on top of background and window, independently of the priority flags in OAM
            and BG Map attributes.
  
  OAM
    Byte3  Flags
      bit3   - Tile VRAM-Bank (0=Bank 0, 1=Bank 1)
      bit2-0 - Palette number (OBP0-7)
    
    The first sprite has the highest priority as opposed to the one with the lowest X coordinate.

Additions

    0xff4d  KEY1 - Prepare Speed Switch [CGB Only]
      bit 7 - Current Speed (0=Normal, 1=Double) (R)
      bit 0 - Prepare Speed Switch (0=No, 1=Prepare) (R/W)

    0xff4f  VBK - VRAM Bank (R/W)
      bit 0 - Currently selected VRAM bank (0=Bank 0, 1=Bank 1) (all other bits are ignored and set to 1)
    
    Needs to go at the end of PpuIoState

  LCD VRAM DMA Transfers
    0xff51  HDMA1 - New DMA Source, High
    0xff52  HDMA2 - New DMA Source, Low
    0xff53  HDMA3 - New DMA Destination, High
    0xff54  HDMA4 - New DMA Destination, Low
    0xff55  HDMA5 - New DMA Length/Mode/Start

    Needs new MemSlot

  0xff56  RP - Infrared Communications Port [CGB Only]

  CGB Palette Memory
    0xff68  BCPS/BGPI - Background Color Palette Specification or Background Palette Index
    0xff69  BCPD/BGPD - Background Color Palette Data or Background Palette Data
    0xff6a  OCPS/OBPI - Object Color Palette Specification or Sprite Palette Index
    0xff6b  OCPD/OBPD - Object Color Palette Data or Sprite Palette Data

    Needs new MemSlot
  
  0xff6c  OPRI - Object Priority Mode [CGB Only]
    bit 0: OBJ Priority Mode (0=OAM Priority, 1=Coordinate Priority) (R/W)
  
  0xff70  SVBK - WRAM Bank [CGB Only]
    In CGB Mode WRAM is 32Kbytes in 8 4Kbyte banks. Bank 0 is always available in memory at 0xc000..0xcfff,
    bank 1..7 can be accessed at 0xd000..0xdfff based on the value in this register.

    bit 0-2 - Select WRAM Bank (R/W)
              Writing a value between 0x00..0x07 will select bank 1..7, writing 0x00 will also select bank 1.
  
  Undocumented registers

    0xff72  Has an initial value of 0x00 (R/W)
    0xff73  Has an initial value of 0x00 (R/W)

    0xff74
      CGB Mode: Has an initial value of 0x00 (R/W)
      DMG Mode: Locked to a value of 0xff (R)

    0xff75
      bit 4-6 - Has an initial value of 0 (R/W)

    0xff76  PCM12 - PCM amplitudes 1 & 2 (R)
      This register is read-only. The low nibble is a copy of sound channel #1's PCM amplitude, the high nibble
      a copy of sound channel #2's.

    0xff77  PCM34 - PCM amplitudes 3 & 4 (R)
      Same, but with channels 3 and 4.

]##
import
  boot,
  gb/dmg/[mem, cpu, apu, timer, ppu, mbc, joypad]



type
  CgbState* = tuple
    testMemory: seq[uint8]
    cpu: CpuState
    timer: TimerState
    ppu: PpuState
    apu: ApuState
    joypad: JoypadState
    cart: MbcState


  Cgb* = ref object
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

proc reset*(self: Cgb, rom: string) =
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
  
  self.cycles = 0

proc reset*(self: Cgb) =
  self.reset(self.cart.data)

proc step*(self: Cgb): bool =
  let
    cycles = self.cpu.step(self.mcu) * 4
  self.cart.step(cycles)
  self.timer.step(cycles)
  self.apu.step(cycles)
  result = self.ppu.step(cycles)
  self.cycles += cycles.uint64


proc save*(self: Cgb): CgbState =
  result.testMemory = self.testMemory
  result.cpu = self.cpu.state
  result.timer = self.timer.state
  result.ppu = self.ppu.state
  result.apu = self.apu.state
  result.joypad = self.joypad.state
  result.cart = self.cart.state

proc load*(self: Cgb, state: CgbState) =
  self.testMemory = state.testMemory
  self.cpu.state = state.cpu
  self.timer.state = state.timer
  self.ppu.state = state.ppu
  self.apu.state = state.apu
  self.joypad.state = state.joypad
  self.cart.state = state.cart


proc newCgb*(bootRom = ""): Cgb =
  let
    mcu = newMcu()
  Cgb(
    mcu: mcu,
    cpu: newCpu(mcu),
    timer: newTimer(mcu),
    ppu: newPpu(mcu),
    apu: newApu(mcu),
    joypad: newJoypad(mcu),
    boot: newBootRom(bootRom),
    cycles: 0
  )
