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
  gb/common/cart,
  mem



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

  Cartridge* = ref object
    header: Cartheader
    data*: string
    state*: MbcState

proc initCartridge*(rom: string): Cartridge =
  let
    header = readCartHeader(rom)
  result = Cartridge(
    header: header,
    data: rom,
    state: MbcState(kind: header.kind)
  )

proc setupMemHandler*(mcu: Mcu, cart: Cartridge) =
  case cart.header.kind:
  of ctRom:
    mcu.initMbcNone(addr cart.data)
  of ctMbc1, ctMbc1Ram, ctMbc1RamBattery:
    mcu.initMbc1(addr cart.state.mbc1, addr cart.data, cart.header.ramSize)
  of ctMbc3, ctMbc3Ram, ctMbc3RamBattery:
    mcu.initMbc3(addr cart.state.mbc3, addr cart.data, cart.header.ramSize)
  else:
    assert false, "Unsupported cartridge type " & $cart.header.kind

proc step*(cart: Cartridge, cycles: int) =
  if cart.header.kind in { ctMbc3, ctMbc3Ram, ctMbc3RamBattery }:
    cart.state.mbc3.mbc3Step(cycles.uint32)
