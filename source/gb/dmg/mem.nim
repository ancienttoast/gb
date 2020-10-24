##[

Memory Controller Unit
======================

Memory map
----------

::
  0x0000-0x7fff
      0x0000-0x3fff ROM Bank 0
          0x0000-0x00ff Interrupt vector table 
          0x0100-0x014f Cartridge header
      0x4000-0x7fff ROM Bank n (switchable)
  0x8000-0x9fff VRAM
  0xa000-0xbfff External RAM
  0xc000-0xdfff Work RAM
      0xc000-0xcfff Work RAM Bank 0
      0xd000-0xdfff Work RAM Bank n (DMG: 1, CGB: switchable)
  0xe000-0xfdff Echo RAM (mirror of 0xc000..0xddff, reserved)
  0xfe00-0xfe9f Object Attribute Memory (OAM)
  0xfea0-0xfeff Not Usable
  0xff00-0xff7f I/O Registers
      0xff00-0xff00 Joypad
      0xff04-0xff07 `Timer and Divider Registers<timer.html>`_
      0xff0f-0xff0f Interrupt Flag Register (IF)
      0xff40-0xff4f LCD IO
      0xff50-0xff50 Boot rom disable flag
  0xff80-0xfffe High RAM (HRAM)
  0xffff-0xffff Interrupts Enable Register (IE)

Sources
-------

* `<http://gameboy.mongenel.com/dmg/asmmemmap.html>`_

]##


const
  MbcRom* = 0x0000'u16..0x7fff'u16
  MbcRam* = 0xa000'u16..0xbfff'u16


type
  MemAddress* = uint16

  MemArea = Slice[MemAddress]

  MemSlot* = enum
    msRom
    msBootRom
    msVRam
    msRam
    msWorkRam
    msEchoRam
    msOam
    msUnusable
    msJoypad
    msTimer
    msInterruptFlag
    msApu
    msLcdIo
    msBootRomFlag
    msHighRam
    msInterruptEnabled
    msDebug

const
  MemSlotSize: array[MemSlot, MemArea] = [
    0x0000'u16..0x7fff'u16,
    0x0000'u16..0x00ff'u16,
    0x8000'u16..0x9fff'u16,
    0xa000'u16..0xbfff'u16,
    0xc000'u16..0xdfff'u16,
    0xe000'u16..0xfdff'u16,
    0xfe00'u16..0xfe9f'u16,
    0xfea0'u16..0xfeff'u16,
    0xff00'u16..0xff00'u16,
    0xff04'u16..0xff07'u16,
    0xff0f'u16..0xff0f'u16,
    0xff10'u16..0xff3f'u16,
    0xff40'u16..0xff4f'u16,
    0xff50'u16..0xff50'u16,
    0xff80'u16..0xfffe'u16,
    0xffff'u16..0xffff'u16,
    0x0000'u16..0xffff'u16
  ]


type
  MemHandler* = ref object
    read*: proc(address: MemAddress): uint8 {.noSideEffect.}
    write*: proc(address: MemAddress, value: uint8) {.noSideEffect.}

  Mcu* = ref object
    handlers: array[MemSlot, MemHandler]

let
  NullHandler = MemHandler(
    read: proc(address: MemAddress): uint8 = 0,
    write: proc(address: MemAddress, value: uint8) = discard
  )


func findHandler(self: Mcu, address: MemAddress): MemHandler =
  result = case address
    of 0x0000..0x7fff:
      if address in MemSlotSize[msBootRom] and self.handlers[msBootRom] != nil:
        self.handlers[msBootRom]
      else:
        self.handlers[msRom]
    of 0x8000..0x9fff: self.handlers[msVRam]
    of 0xa000..0xbfff: self.handlers[msRam]
    of 0xc000..0xdfff: self.handlers[msWorkRam]
    of 0xe000..0xfdff: self.handlers[msEchoRam]
    of 0xfe00..0xfe9f: self.handlers[msOam]
    of 0xfea0..0xfeff: self.handlers[msUnusable]
    of 0xff00..0xff00: self.handlers[msJoypad]
    of 0xff04..0xff07: self.handlers[msTimer]
    of 0xff0f..0xff0f: self.handlers[msInterruptFlag]
    of 0xff10..0xff3f: self.handlers[msApu]
    of 0xff40..0xff4f: self.handlers[msLcdIo]
    of 0xff50..0xff50: self.handlers[msBootRomFlag]
    of 0xff80..0xfffe: self.handlers[msHighRam]
    of 0xffff..0xffff: self.handlers[msInterruptEnabled]
    else: self.handlers[msDebug]
  if result == nil:
    result = self.handlers[msDebug]
  if result == nil:
    result = MemHandler(
      read: proc(address: MemAddress): uint8 = 0,
      write: proc(address: MemAddress, value: uint8) = discard
    )

func read*(self: Mcu, address: MemAddress): uint8 =
  let
    newHandler = self.findHandler(address)
  newHandler.read(address)

func write*(self: Mcu, address: MemAddress, value: uint8) =
  let
    newHandler = self.findHandler(address)
  newHandler.write(address, value)

func `[]`*(self: Mcu, address: MemAddress): uint8 =
  self.read(address)

func `[]=`*(self: Mcu, address: MemAddress, value: uint8) =
  self.write(address, value)

func `[]=`*(self: Mcu, address: MemAddress, value: uint16) =
  self[address+0] = (value and 0x00ff).uint8
  self[address+1] = ((value and 0xff00) shr 8).uint8


proc clearHandler*(self: Mcu, slot: MemSlot) =
  self.handlers[slot] = nil

proc clearHandlers*(self: Mcu) =
  for slot in MemSlot:
    self.clearHandler(slot)

proc createHandlerFor*[T: tuple | object | array | uint8](slot: MemSlot, obj: ptr T): MemHandler =
  assert MemSlotSize[slot].len == sizeof(T)
  var
    data = cast[ptr array[sizeof(T), uint8]](obj)
  MemHandler(
    read: proc(address: MemAddress): uint8 = data[(address - MemSlotSize[slot].a).int],
    write: proc(address: MemAddress, value: uint8) = data[(address - MemSlotSize[slot].a).int] = value
  )

proc setHandler*(self: Mcu, slot: MemSlot, handler: MemHandler) =
  self.handlers[slot] = handler

proc setHandler*(self: Mcu, slot: MemSlot, values: ptr seq[uint8]) =
  # TODO: This is only commented out for the tests
  #assert MemSlotSize[slot].len == values[].len
  self.setHandler(slot,
    MemHandler(
      read: proc(address: MemAddress): uint8 = values[(address - MemSlotSize[slot].a).int],
      write: proc(address: MemAddress, value: uint8) = values[(address - MemSlotSize[slot].a).int] = value,
    )
  )

proc setHandler*[T: tuple | object | array | uint8](self: Mcu, slot: MemSlot, obj: ptr T) =
  self.setHandler(slot, createHandlerFor(slot, obj))


proc newMcu*(): Mcu =
  result = Mcu()
  result.setHandler(msDebug, NullHandler)

proc newMcu*(values: ptr seq[uint8]): Mcu =
  result = newMcu()
  result.setHandler(msDebug, values)
