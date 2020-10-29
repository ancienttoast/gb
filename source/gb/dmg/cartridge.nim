##[

Cartridges and Memory Bank Controllers
======================================

Memory map
----------

=================  =========================
  Address            Description
=================  =========================
  0x0100-0x0103      Entry Point
  0x0104-0x0133      Nintendo Logo
  0x0134-0x0143      Title
  0x0144-0x0145      New Licensee Code
  0x0146             SGB Flag
  0x0147             Cartridge Type
  0x0148             ROM Size
  0x0149             RAM Size
  0x014a             Destination Code
  0x014b             Old Licensee Code
  0x014c             Mask ROM Version number
  0x014d             Header Checksum
  0x014e-0x014f      Global Checksum
=================  =========================

*CGB* specifies a special meaning for the Title section

===============  =========================
  Address          Description
===============  =========================
0x013f-0x0142    Manufacturer Code
0x0143           CGB Flag
===============  =========================

Sources
-------

* `<https://gbdev.io/pandocs/#the-cartridge-header>`_

]##
import
  mem



type
  CartridgeType = enum
    ctRom = 0x00
    ctMbc1 = 0x01
    ctMbc1Ram = 0x02
    ctMbc1RamBattery = 0x03
    ctMbc2 = 0x05
    ctMbc2Battery = 0x06
    ctRomRam = 0x08
    ctRomRamBattery = 0x09
    ctMMM01 = 0x0b
    ctMMM01Ram = 0x0c
    ctMMM01RamBattery = 0x0d
    ctMbc3TimerBattery = 0x0f
    ctMbc3TimerRamBattery = 0x10
    ctMbc3 = 0x11
    ctMbc3Ram = 0x12
    ctMbc3RamBattery = 0x13
    ctMbc5 = 0x19
    ctMbc5Battery = 0x1a
    ctMbc5RamBattery = 0x1b
    ctMbc5Rumble = 0x1c
    ctMbc5RumbleRam = 0x1d
    ctMbc5RumbleRamBattery = 0x1e
    ctMbc6 = 0x20
    ctMbc7SensorRumbleRamBattery = 0x22
    ctPocketCamera = 0xfc
    ctBandaiTamas = 0xfd
    ctHuc3 = 0xfe
    ctHuc1RamBattery = 0xff
  
  CartridgeRomSize = enum
    crs32KByte  = 0x00 ## 32KByte (no ROM banking)
    crs64KByte  = 0x01 ## 64KByte (4 banks)
    crs128KByte = 0x02 ## 128KByte (8 banks)
    crs256KByte = 0x03 ## 256KByte (16 banks)
    crs512KByte = 0x04 ## 512KByte (32 banks)
    crs1MByte   = 0x05 ## 1MByte (64 banks)  - only 63 banks used by MBC1
    crs2MByte   = 0x06 ## 2MByte (128 banks) - only 125 banks used by MBC1
    crs4MByte   = 0x07 ## 4MByte (256 banks)
    crs8MByte   = 0x08 ## 8MByte (512 banks)
    crs11MByte  = 0x52 ## 1.1MByte (72 banks)
    crs12MByte  = 0x53 ## 1.2MByte (80 banks)
    crs15MByte  = 0x54 ## 1.5MByte (96 banks)
  
  CartridgeRamSize = enum
    crsNone      = 0x00
    crs2KBytes   = 0x01 ## 2 KBytes
    crs8Kbytes   = 0x02 ## 8 Kbytes
    crs32KBytes  = 0x03 ## 32 KBytes (4 banks of 8KBytes each)
    crs128KBytes = 0x04 ## 128 KBytes (16 banks of 8KBytes each)
    crs64KBytes  = 0x05 ## 64 KBytes (8 banks of 8KBytes each)


const
  RomBankSize = 16_384
  RamBankSize = 8_192
  # TODO: use CartridgeRomSize somehow
  #RomSize: array[0..11, int] = [ 32_768, 65_536, 131_072, 262_144, 524_288, 1_048_576, 2_097_152, 4_194_304, 8_388_608, 1_179_648, 1_310_720, 1_572_864 ]
  RamSize: array[CartridgeRamSize, int] = [ 0, 2_048, 8_192, 32_768, 131_072, 65_536 ]





#[########################################################################################

    None

########################################################################################]#

proc initMbcNone(mcu: Mcu, data: ptr string) =
  assert data[].len == RomBankSize*2
  let
    handler = MemHandler(
      read: proc(address: MemAddress): uint8 =
        data[address.int].uint8,
      write: proc(address: MemAddress, value: uint8) =
        discard
    )
  mcu.setHandler(msRom, handler)



#[########################################################################################

    MBC1

########################################################################################]#

type
  Mbc1State = tuple
    ram: seq[uint8]
    ramEnable: bool
    ramBank: uint8
    romBank: uint8
    select: int

proc initMbc1(mcu: Mcu, state: ptr Mbc1State, rom: ptr string, ramSize: CartridgeRamSize) =
  proc romReadHandler(address: MemAddress): uint8 =
    case address
    of 0x0000'u16..0x3fff'u16:
      cast[uint8](rom[address.int])
    of 0x4000'u16..0x7fff'u16:
      let
        p = address - 0x4000
      cast[uint8](rom[(state.romBank.int * RomBankSize) + p.int])
    else:
      0'u8
  
  proc romWriteHandler(address: MemAddress, value: uint8) =
    case address
    of 0x0000'u16..0x1fff'u16:
      if ramSize != crsNone:
        state.ramEnable = (value and 0x0f) == 0x0a
    of 0x2000'u16..0x3fff'u16:
      state.romBank = state.romBank and 0b11100000
      state.romBank = state.romBank or (value and 0b00011111)
      if state.romBank in { 0x00, 0x20, 0x40, 0x60 }:
        # handle MBC1 rom select bug where any attempt to address banks
        # 0x00, 0x20, 0x40 or 0x60 will address 0x01, 0x21, 0x41, 0x61 instead
        state.romBank += 1
    of 0x4000'u16..0x5fff'u16:
      if value in { 0x00, 0x01, 0x02, 0x03 }:
        state.ramBank = value
    of 0x6000'u16..0x7fff'u16:
      assert value in {0, 1}
      state.select = value.int
    else:
      discard

  state.romBank = 1
  state.select = 0
  if ramSize != crsNone:
    state.ramBank = 0
    state.ramEnable = false
    state.ram = newSeq[uint8](RamSize[ramSize])
  let
    romHandler = MemHandler(
      read: romReadHandler,
      write: romWriteHandler
    )
  mcu.setHandler(msRom, romHandler)
  if ramSize != crsNone:
    let
      ramHandler = MemHandler(
        read: proc(address: MemAddress): uint8 =
          if not state.ramEnable:
            return 0
          let
            p = (state.ramBank * RamBankSize) + (address - 0xa000)
          if p.int > state.ram.high:
            0'u8
          else:
            state.ram[p]
        ,
        write: proc(address: MemAddress, value: uint8) =
          if not state.ramEnable:
            return
          let
            p = (state.ramBank * RomBankSize) + (address - 0xa000)
          if p.int <= state.ram.high:
            state.ram[p] = value
      )
    mcu.setHandler(msRam, ramHandler)



#[########################################################################################

    MBC3

########################################################################################]#

type
  Mbc3RtcData = enum
    rdS,
    rdM,
    rdH,
    rdDL,
    rdDH,
    rdInvalid

  # 4194304 / 32768 = 128
  Mbc3State = tuple
    ram: seq[uint8]
    ramEnable: bool
    ramBank: uint8
    romBank: uint8
    rtcMode: Mbc3RtcData
    rtcState: array[5, uint8]
    rtcCounter: uint64

proc initMbc3(mcu: Mcu, state: ptr Mbc3State, rom: ptr string, ramSize: CartridgeRamSize) =
  proc romReadHandler(address: MemAddress): uint8 =
    case address
    of 0x0000'u16..0x3fff'u16:
      cast[uint8](rom[address.int])
    of 0x4000'u16..0x7fff'u16:
      let
        p = address - 0x4000
      cast[uint8](rom[(state.romBank.int * RomBankSize) + p.int])
    else:
      0'u8
  
  proc romWriteHandler(address: MemAddress, value: uint8) =
    case address
    of 0x0000'u16..0x1fff'u16:
      if ramSize != crsNone:
        state.ramEnable = (value and 0x0f) == 0x0a
    of 0x2000'u16..0x3fff'u16:
      state.romBank = value and 0b01111111
      if state.romBank == 0x00:
        state.romBank += 1
    of 0x4000'u16..0x5fff'u16:
      if value in 0x00'u8..0x03'u8:
        state.ramBank = value
        state.rtcMode = rdInvalid
      elif value in 0x08'u8..0x0c'u8:
        state.rtcMode = (value - 0x08).Mbc3RtcData
    of 0x6000'u16..0x7fff'u16:
      discard
      # TODO: extract time from rtcCounter
    else:
      discard

  state.romBank = 1
  state.rtcMode = rdInvalid
  if ramSize != crsNone:
    state.ramBank = 0
    state.ramEnable = false
    state.ram = newSeq[uint8](RamSize[ramSize])
  let
    romHandler = MemHandler(
      read: romReadHandler,
      write: romWriteHandler
    )
  mcu.setHandler(msRom, romHandler)
  if ramSize != crsNone:
    let
      ramHandler = MemHandler(
        read: proc(address: MemAddress): uint8 =
          if not state.ramEnable:
            return 0
          if state.rtcMode != rdInvalid:
            return state.rtcState[state.rtcMode.ord()]
          let
            p = (state.ramBank * RamBankSize) + (address - 0xa000)
          if p.int > state.ram.high:
            0'u8
          else:
            state.ram[p]
        ,
        write: proc(address: MemAddress, value: uint8) =
          if not state.ramEnable:
            return
          let
            p = (state.ramBank * RomBankSize) + (address - 0xa000)
          if p.int <= state.ram.high:
            state.ram[p] = value
      )
    mcu.setHandler(msRam, ramHandler)

proc mbc3Step(state: var Mbc3State, cycles: uint32) =
  const
    Period = 371085174374400'u64
  state.rtcCounter += cycles
  while state.rtcCounter >= Period:
    state.rtcCounter -= Period




type
  MbcState* = object
    case kind: CartridgeType
    of ctRom, ctRomRam, ctRomRamBattery:
      discard
    of ctMbc1, ctMbc1Ram, ctMbc1RamBattery:
      mbc1: Mbc1State
    of ctMbc3, ctMbc3Ram, ctMbc3RamBattery:
      mbc3: Mbc3State
    else:
      discard

  CartridgeInfo = tuple
    kind: CartridgeType
    romSize: CartridgeRomSize
    ramSize: CartridgeRamSize
    title: string
    version: uint8

  Cartridge* = ref object
    info: CartridgeInfo
    data*: string
    state*: MbcState

proc initCartridge*(rom: string): Cartridge =
  let
    data = rom
    info = (
      kind: data[0x0147].CartridgeType,
      romSize: data[0x0148].CartridgeRomSize,
      ramSize: data[0x0149].CartridgeRamSize,
      title: $data[0x0134..0x0143],
      version: data[0x014c].uint8,
    )
  result = Cartridge(
    info: info,
    data: data,
    state: MbcState(kind: info.kind)
  )

proc setupMemHandler*(mcu: Mcu, cart: Cartridge) =
  case cart.info.kind:
  of ctRom:
    mcu.initMbcNone(addr cart.data)
  of ctMbc1, ctMbc1Ram, ctMbc1RamBattery:
    mcu.initMbc1(addr cart.state.mbc1, addr cart.data, cart.info.ramSize)
  of ctMbc3, ctMbc3Ram, ctMbc3RamBattery:
    mcu.initMbc3(addr cart.state.mbc3, addr cart.data, cart.info.ramSize)
  else:
    assert false, "Unsupported cartridge type " & $cart.info.kind

proc step*(cart: Cartridge, cycles: int) =
  if cart.info.kind in { ctMbc3, ctMbc3Ram, ctMbc3RamBattery }:
    cart.state.mbc3.mbc3Step(cycles.uint32)
