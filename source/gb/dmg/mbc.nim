##[

Memory Bank Controllers
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



type
  Mbc1State = tuple
    ram: seq[uint8]
    ramEnable: bool
    ramBank: uint8
    romBank: uint8
    select: int


  Mbc3RtcData = enum
    rdS,
    rdM,
    rdH,
    rdDL,
    rdDH,
    rdInvalid

  Mbc3State = tuple
    ram: seq[uint8]
    ramEnable: bool
    ramBank: uint8
    romBank: uint8
    rtcMode: Mbc3RtcData
    rtcState: array[5, uint8]
    rtcCounter: uint64


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

const
  MbcRom* = 0x0000'u16..0x7fff'u16
  MbcRam* = 0xa000'u16..0xbfff'u16

template toRamDataOffset(address: MemAddress, bank: uint8): MemAddress =
  (RamBankSize * bank.uint16) + (address - MbcRam.a)



#[########################################################################################

    None

########################################################################################]#
proc initMbcNone(mcu: Mcu, cart: Cartridge) =
  assert cart.data.len == RomBankSize*2
  let
    handler = MemHandler(
      read: proc(address: MemAddress): uint8 =
        cart.data[address.int].uint8,
      write: proc(address: MemAddress, value: uint8) =
        discard
    )
  mcu.setHandler(msRom, handler)



#[########################################################################################

    MBC1

########################################################################################]#
proc mbc1RomHandler(cart: Cartridge): MemHandler =
  MemHandler(
    read: proc(address: MemAddress): uint8 =
      case address
      of 0x0000'u16..0x3fff'u16:
        cast[uint8](cart.data[address.int])
      of 0x4000'u16..0x7fff'u16:
        let
          p = address - 0x4000
        cast[uint8](cart.data[(cart.state.mbc1.romBank.int * RomBankSize) + p.int])
      else:
        0'u8
    ,
    write: proc(address: MemAddress, value: uint8) =
      case address
      of 0x0000'u16..0x1fff'u16:
        if cart.header.ramSize != crsNone:
          cart.state.mbc1.ramEnable = (value and 0x0f) == 0x0a
      of 0x2000'u16..0x3fff'u16:
        cart.state.mbc1.romBank = cart.state.mbc1.romBank and 0b11100000
        cart.state.mbc1.romBank = cart.state.mbc1.romBank or (value and 0b00011111)
        if cart.state.mbc1.romBank in { 0x00, 0x20, 0x40, 0x60 }:
          # handle MBC1 rom select bug where any attempt to address banks
          # 0x00, 0x20, 0x40 or 0x60 will address 0x01, 0x21, 0x41, 0x61 instead
          cart.state.mbc1.romBank += 1
      of 0x4000'u16..0x5fff'u16:
        if value in { 0x00, 0x01, 0x02, 0x03 }:
          cart.state.mbc1.ramBank = value
      of 0x6000'u16..0x7fff'u16:
        assert value in {0, 1}
        cart.state.mbc1.select = value.int
      else:
        discard
  )

proc mbc1RamHandler(cart: Cartridge): MemHandler =
  if cart.header.ramSize != crsNone:
    MemHandler(
      read: proc(address: MemAddress): uint8 =
        if not cart.state.mbc1.ramEnable:
          return 0
        let
          p = address.toRamDataOffset(cart.state.mbc1.ramBank)
        if p.int > cart.state.mbc1.ram.high:
          0'u8
        else:
          cart.state.mbc1.ram[p]
      ,
      write: proc(address: MemAddress, value: uint8) =
        if not cart.state.mbc1.ramEnable:
          return
        let
          p = (cart.state.mbc1.ramBank * RomBankSize) + (address - 0xa000)
        if p.int <= cart.state.mbc1.ram.high:
          cart.state.mbc1.ram[p] = value
    )
  else:
    NullHandler

proc initMbc1(mcu: Mcu, cart: Cartridge) =
  cart.state.mbc1.romBank = 1
  cart.state.mbc1.select = 0
  if cart.header.ramSize != crsNone:
    cart.state.mbc1.ramBank = 0
    cart.state.mbc1.ramEnable = false
    cart.state.mbc1.ram = newSeq[uint8](RamSize[cart.header.ramSize])

  mcu.setHandler(msRom, cart.mbc1RomHandler())
  mcu.setHandler(msRam, cart.mbc1RamHandler())



#[########################################################################################

    MBC3

########################################################################################]#
proc mbc3RomHandler(cart: Cartridge): MemHandler =
  MemHandler(
    read: proc(address: MemAddress): uint8 =
      case address
      of 0x0000'u16..0x3fff'u16:
        cast[uint8](cart.data[address.int])
      of 0x4000'u16..0x7fff'u16:
        let
          p = address - 0x4000
        cast[uint8](cart.data[(cart.state.mbc3.romBank.int * RomBankSize) + p.int])
      else:
        0'u8
    ,
    write: proc(address: MemAddress, value: uint8) =
      case address
      of 0x0000'u16..0x1fff'u16:
        if cart.header.ramSize != crsNone:
          cart.state.mbc3.ramEnable = (value and 0x0f) == 0x0a
      of 0x2000'u16..0x3fff'u16:
        cart.state.mbc3.romBank = value and 0b01111111
        if cart.state.mbc3.romBank == 0x00:
          cart.state.mbc3.romBank += 1
      of 0x4000'u16..0x5fff'u16:
        if value in 0x00'u8..0x03'u8:
          cart.state.mbc3.ramBank = value
          cart.state.mbc3.rtcMode = rdInvalid
        elif value in 0x08'u8..0x0c'u8:
          cart.state.mbc3.rtcMode = (value - 0x08).Mbc3RtcData
      of 0x6000'u16..0x7fff'u16:
        discard
        # TODO: extract time from rtcCounter
      else:
        discard
  )

proc mbc3RamHandler(cart: Cartridge): MemHandler =
  if cart.header.ramSize != crsNone:
    MemHandler(
      read: proc(address: MemAddress): uint8 =
        if not cart.state.mbc3.ramEnable:
          return 0
        if cart.state.mbc3.rtcMode != rdInvalid:
          return cart.state.mbc3.rtcState[cart.state.mbc3.rtcMode.ord()]
        let
          p = address.toRamDataOffset(cart.state.mbc3.ramBank)
        if p.int > cart.state.mbc3.ram.high:
          0'u8
        else:
          cart.state.mbc3.ram[p]
      ,
      write: proc(address: MemAddress, value: uint8) =
        if not cart.state.mbc3.ramEnable:
          return
        let
          p = address.toRamDataOffset(cart.state.mbc3.ramBank)
        if p.int <= cart.state.mbc3.ram.high:
          cart.state.mbc3.ram[p] = value
    )
  else:
    NullHandler

proc initMbc3(mcu: Mcu, cart: Cartridge) =
  cart.state.mbc3.romBank = 1
  cart.state.mbc3.rtcMode = rdInvalid
  if cart.header.ramSize != crsNone:
    cart.state.mbc3.ramBank = 0
    cart.state.mbc3.ramEnable = false
    cart.state.mbc3.ram = newSeq[uint8](RamSize[cart.header.ramSize])

  mcu.setHandler(msRom, cart.mbc3RomHandler())
  mcu.setHandler(msRam, cart.mbc3RamHandler())

proc mbc3Step(state: var Mbc3State, cycles: uint32) =
  const
    Period = 371085174374400'u64
  state.rtcCounter += cycles
  while state.rtcCounter >= Period:
    state.rtcCounter -= Period

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
    mcu.initMbcNone(cart)
  of ctMbc1, ctMbc1Ram, ctMbc1RamBattery:
    mcu.initMbc1(cart)
  of ctMbc3, ctMbc3Ram, ctMbc3RamBattery:
    mcu.initMbc3(cart)
  else:
    assert false, "Unsupported cartridge type " & $cart.header.kind

proc step*(cart: Cartridge, cycles: int) =
  case cart.header.kind:
  of ctRom, ctMbc1, ctMbc1Ram, ctMbc1RamBattery:
    # Nothing to update for these MBC types
    discard
  of ctMbc3, ctMbc3Ram, ctMbc3RamBattery:
    cart.state.mbc3.mbc3Step(cycles.uint32)
  else:
    assert false, "Unsupported cartridge type " & $cart.header.kind