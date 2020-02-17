##[

  0x0000-0x7fff
      0x0000-0x3fff ROM Bank 0
          0x0000-0x00ff Interrupt vector table 
          0x0100-0x014f Cartridge header
      0x4000-0x7fff ROM Bank n (switchable)
  0x8000-0x9fff VRAM
  0xa000-0xbfff External RAM
  0xc000-0xcfff Work RAM Bank 0
  0xd000-0xdfff Work RAM Bank n (DMG: 1, CGB: switchable)
  0xe000-0xfdff Echo RAM (mirror of 0xc000~0xddff, reserved)
  0xfe00-0xde9f Object Attribute Memory (OAM)
  0xfea0-0xfeff Not Usable
  0xff00-0xff7f I/O Registers
      0xff04-0xff07 `Timer and Divider Registers<timer.html>`_
      0xff40-0x???? LCD
  0xff80-0xfffe High RAM (HRAM)
  0xffff-0xffff Interrupts Enable Register (IE)

  `http://gameboy.mongenel.com/dmg/asmmemmap.html`

]##
type
  MemAddress* = uint16

  MemArea = Slice[MemAddress]

  MemHandler* = object
    read*: proc(address: MemAddress): uint8 {.noSideEffect.}
    write*: proc(address: MemAddress, value: uint8) {.noSideEffect.}
    area*: MemArea

  Mcu* = ref object
    handlers: seq[MemHandler]

proc pushHandler*(self: Mcu, handler: MemHandler) =
  self.handlers &= handler

proc popHandler*(self: Mcu) =
  discard self.handlers.pop()

proc pushHandler*(self: Mcu, area: MemArea, constant: uint8) =
  self.pushHandler(
    MemHandler(
      read: proc(address: MemAddress): uint8 = constant,
      write: proc(address: MemAddress, value: uint8) = discard,
      area: area
    )
  )

proc pushHandler*(self: Mcu, start: MemAddress, values: ptr seq[uint8]) =
  self.pushHandler(
    MemHandler(
      read: proc(address: MemAddress): uint8 = values[(address - start).int],
      write: proc(address: MemAddress, value: uint8) = values[(address - start).int] = value,
      area: start..(start+values[].high.MemAddress)
    )
  )

proc pushHandler*[T: object | tuple](self: Mcu, start: MemAddress, obj: ptr T) =
  var
    data = cast[ptr array[sizeof(T), uint8]](obj)
  self.pushHandler(
    MemHandler(
      read: proc(address: MemAddress): uint8 = data[(address - start).int],
      write: proc(address: MemAddress, value: uint8) = data[(address - start).int] = value,
      area: start..(start+sizeof(T).MemAddress-1)
    )
  )

func read*(self: Mcu, address: MemAddress): uint8 =
  for i in countdown(self.handlers.high, 0):
    let
      handler = self.handlers[i]
    if address in handler.area:
      return handler.read(address)
  # TODO: error handling
  return 0

func write*(self: Mcu, address: MemAddress, value: uint8) =
  for i in countdown(self.handlers.high, 0):
    let
      handler = self.handlers[i]
    if address in handler.area:
      handler.write(address, value)
      return
  # TODO: error handling

func `[]`*(self: Mcu, address: MemAddress): uint8 =
  self.read(address)

func `[]=`*(self: Mcu, address: MemAddress, value: uint8) =
  self.write(address, value)

func `[]=`*(self: Mcu, address: MemAddress, value: uint16) =
  self[address+0] = (value and 0x00ff).uint8
  self[address+1] = ((value and 0xff00) shr 8).uint8

proc newMcu*(): Mcu =
  result = Mcu(
    handlers: newSeq[MemHandler]()
  )
  result.pushHandler(0'u16..MemAddress.high.MemAddress, 0)

proc newMcu*(values: ptr seq[uint8]): Mcu =
  result = newMcu()
  result.pushHandler(0, values)
