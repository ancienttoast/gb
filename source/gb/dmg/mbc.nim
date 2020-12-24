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
  std/times,
  gb/common/[cart, util],
  mem



type
  Mbc3RtcData = enum
    rdSeconds,
    rdMinutes,
    rdHours,
    rdDays,
    rdFlags,
    rdInvalid

  Mbc3Clock = tuple
    seconds:  uint8   ## 0x08  RTC S   Seconds   0-59
    minutes:  uint8   ## 0x09  RTC M   Minutes   0-59
    hours:    uint8   ## 0x0a  RTC H   Hours     0-23
    days:     uint8   ## 0x0b  RTC DL  Lower 8 bits of Day Counter (0-FFh)
    flags:    uint8   ## 0x0c  RTC DH  Upper 1 bit of Day Counter, Carry Bit, Halt Flag
                      ##   bit 0  Most significant bit of Day Counter (Bit 8)
                      ##   bit 6  Halt (0=Active, 1=Stop Timer)
                      ##   bit 7  Day Counter Carry Bit (1=Counter Overflow)

func isActive(self: Mbc3Clock): bool =
  not self.flags.testBit(6)

func inc(rtc: var Mbc3Clock) =
  var
    overflow = rtc.seconds.inc(0'u8..59'u8)
  if overflow:
    overflow = rtc.minutes.inc(0'u8..59'u8)
  if overflow:
    overflow = rtc.hours.inc(0'u8..23'u8)
  if overflow:
    overflow = rtc.days.inc(0'u8..255'u8)
  if overflow:
    if rtc.flags.testBit(0):
      rtc.flags.setBit(7)
    else:
      rtc.flags.setBit(0)



type
  Mbc1State = tuple
    ram: seq[uint8]
    ramEnable: bool
    ramBank: uint8
    romBank: uint8
    select: int

  Mbc3State = tuple
    ram: seq[uint8]
    ramEnable: bool
    ramBank: uint8          ## Currently selected RAM bank
    romBank: uint8          ## Currently selected ROM bank
    rtcMode: Mbc3RtcData
    rtcClock: Mbc3Clock
    rtcCounter: uint32
    rtcLatch: Mbc3Clock
    rtcPrepareLatch: bool


  MbcState* = object
    case kind*: CartridgeType
    of ctRom:
      discard
    of ctMbc1, ctMbc1Ram, ctMbc1RamBattery:
      mbc1*: Mbc1State
    of ctMbc3, ctMbc3Ram, ctMbc3RamBattery, ctMbc3TimerBattery, ctMbc3TimerRamBattery:
      mbc3*: Mbc3State
    else:
      discard

  Cartridge* = ref object
    header*: Cartheader
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


    Sources
    -------

    * `<https://gbdev.io/pandocs/#mbc3>`_

########################################################################################]#
proc mbc3RomHandler(cart: Cartridge): MemHandler =
  MemHandler(
    read: proc(address: MemAddress): uint8 =
      case address
      of 0x0000'u16..0x3fff'u16:
        cart.data[address.int].uint8
      of 0x4000'u16..0x7fff'u16:
        let
          p = address - 0x4000
        cart.data[(cart.state.mbc3.romBank.int * RomBankSize) + p.int].uint8
      else:
        0'u8
    ,
    write: proc(address: MemAddress, value: uint8) =
      case address
      of 0x0000'u16..0x1fff'u16:
        ## RAM and Timer Enable  [W]
        ##   Mostly the same as for MBC1, a value of 0x0a will enable reading and writing to
        ##   external RAM - and to the RTC Registers! A value of 0x00 will disable either.
        if cart.header.ramSize != crsNone:
          cart.state.mbc3.ramEnable = value == 0x0a
      of 0x2000'u16..0x3fff'u16:
        ## ROM Bank Number  [W]
        ##   Same as for MBC1, except that the whole 7 bits of the RAM Bank Number are written
        ##   directly to this address. As for the MBC1, writing a value of 00h, will select
        ##   Bank 0x01 instead. All other values 0x01-0x7f select the corresponding ROM Banks.
        cart.state.mbc3.romBank = max(value and 0b01111111, 1)
      of 0x4000'u16..0x5fff'u16:
        ## RAM Bank Number - or - RTC Register Select  [W]
        ##   As for the MBC1s RAM Banking Mode, writing a value in range for 00h-03h maps the
        ##   corresponding external RAM Bank (if any) into memory at 0xa000-0xbfff. When writing
        ##   a value of 0x08-0x0c, this will map the corresponding RTC register into memory at
        ##   0xa000-0xbfff. That register could then be read/written by accessing any address in
        ##   that area, typically that is done by using address 0xa000.
        if value in 0'u8..3'u8:
          cart.state.mbc3.ramBank = value
          cart.state.mbc3.rtcMode = rdInvalid
        elif value in 0x08'u8..0x0c'u8:
          cart.state.mbc3.rtcMode = (value - 0x08).Mbc3RtcData
      of 0x6000'u16..0x7fff'u16:
        ## Latch Clock Data  [W]
        ##   When writing 0x00, and then 0x01 to this register, the current time becomes latched into the
        ##   RTC registers. The latched data will not change until it becomes latched again, by repeating
        ##   the write 0x00->0x01 procedure.
        if value == 1 and cart.state.mbc3.rtcPrepareLatch:
          cart.state.mbc3.rtcLatch = cart.state.mbc3.rtcClock
        cart.state.mbc3.rtcPrepareLatch = value == 0
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
          return cast[array[5, uint8]](cart.state.mbc3.rtcLatch)[cart.state.mbc3.rtcMode.ord()]
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
        if cart.state.mbc3.rtcMode != rdInvalid:
          cast[ptr array[5, uint8]](addr cart.state.mbc3.rtcClock)[cart.state.mbc3.rtcMode.ord()] = value
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
    Period = 4194304
  state.rtcCounter += cycles
  while state.rtcCounter >= Period:
    state.rtcCounter -= Period
    if state.rtcClock.isActive:
      state.rtcClock.inc





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
  of ctMbc3, ctMbc3Ram, ctMbc3RamBattery, ctMbc3TimerBattery, ctMbc3TimerRamBattery:
    mcu.initMbc3(cart)
  else:
    assert false, "Unsupported cartridge type " & $cart.header.kind

proc step*(cart: Cartridge, cycles: int) =
  case cart.header.kind:
  of ctRom, ctMbc1, ctMbc1Ram, ctMbc1RamBattery:
    # Nothing to update for these MBC types
    discard
  of ctMbc3, ctMbc3Ram, ctMbc3RamBattery, ctMbc3TimerBattery, ctMbc3TimerRamBattery:
    cart.state.mbc3.mbc3Step(cycles.uint32)
  else:
    assert false, "Unsupported cartridge type " & $cart.header.kind