##[

General Internal Memory

  00000000-00003fff   BIOS - System ROM         (16 KBytes)
  00004000-01ffffff   Not used
  02000000-0203ffff   WRAM - On-board Work RAM  (256 KBytes) 2 Wait
  02040000-02ffffff   Not used
  03000000-03007fff   WRAM - On-chip Work RAM   (32 KBytes)
  03008000-03ffffff   Not used
  04000000-040003fE   I/O Registers
  04000400-04ffffff   Not used

Internal Display Memory

  05000000-050003ff   BG/OBJ Palette RAM        (1 Kbyte)
  05000400-05ffffff   Not used
  06000000-06017fff   VRAM - Video RAM          (96 KBytes)
  06018000-06ffffff   Not used
  07000000-070003ff   OAM - OBJ Attributes      (1 Kbyte)
  07000400-07ffffff   Not used

External Memory (Game Pak)

  0x08000000-0x09ffffff   Game Pak ROM/FlashROM (max 32MB) - Wait State 0
  0x0a000000-0x0bffffff   Game Pak ROM/FlashROM (max 32MB) - Wait State 1
  0x0c000000-0x0dffffff   Game Pak ROM/FlashROM (max 32MB) - Wait State 2
  0x0e000000-0x0e00ffff   Game Pak SRAM    (max 64 KBytes) - 8bit Bus width
  0x0e010000-0x0fffffff   Not used

Unused Memory Area

  10000000-ffffffff   Not used (upper 4bits of address bus unused)


  * `https://problemkaputt.de/gbatek.htm#gbamemorymap`_

]##
type
  MemAddress* = uint32

  MemArea = Slice[MemAddress]

  MemSlot* = enum
    # General Internal Memory
    msBios
    msWramOnBoard
    msWramOnChip
    wsIO
    # Internal Display Memory
    msVPaletteRam
    msVram
    msVObj
    # External Memory (Game Pak)
    msGamePakRom0,
    msGamePakRom1,
    msGamePakRom2,
    msGamePakSram,
    msDebug

const
  MemSlotSize: array[MemSlot, MemArea] = [
    # General Internal Memory
    0x00000000'u32..0x00003fff'u32,
    0x02000000'u32..0x0203ffff'u32,
    0x03000000'u32..0x03007fff'u32,
    0x04000000'u32..0x040003fe'u32,
    # Internal Display Memory
    0x05000000'u32..0x050003ff'u32,
    0x06000000'u32..0x06017fff'u32,
    0x07000000'u32..0x070003ff'u32,
    # External Memory (Game Pak)
    0x08000000'u32..0x09ffffff'u32,
    0x0a000000'u32..0x0bffffff'u32,
    0x0c000000'u32..0x0dffffff'u32,
    0x0e000000'u32..0x0e00ffff'u32,
    0x00000000'u32..0xffffffff'u32
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
    of 0x00000000..0x00003fff: self.handlers[msBios]
    of 0x02000000..0x0203ffff: self.handlers[msWramOnBoard]
    of 0x03000000..0x03007fff: self.handlers[msWramOnChip]
    of 0x04000000..0x040003fe: self.handlers[wsIO]
    of 0x05000000..0x050003ff: self.handlers[msVPaletteRam]
    of 0x06000000..0x06017fff: self.handlers[msVram]
    of 0x07000000..0x070003ff: self.handlers[msVObj]
    of 0x08000000..0x09ffffff: self.handlers[msGamePakRom0]
    of 0x0a000000..0x0bffffff: self.handlers[msGamePakRom1]
    of 0x0c000000..0x0dffffff: self.handlers[msGamePakRom2]
    of 0x0e000000..0x0e00ffff: self.handlers[msGamePakSram]
    else: self.handlers[msDebug]
  if result == nil:
    result = self.handlers[msDebug]
  if result == nil:
    result = MemHandler(
      read: proc(address: MemAddress): uint8 = 0,
      write: proc(address: MemAddress, value: uint8) = discard
    )

func readImpl(self: Mcu, address: MemAddress): uint8 =
  let
    handler = self.findHandler(address)
  handler.read(address)

func read*[T: uint8 | uint16 | uint32](self: Mcu, address: MemAddress): T =
  # TODO: only works on little endian architectures
  when T is uint8:
    result = self.readImpl(address)
  elif T is uint16:
    result =
      self.readImpl(address + 1).T shl 8 or
      self.readImpl(address + 0)
  elif T is uint32:
    result =
      self.readImpl(address + 3).T shl 24 or
      self.readImpl(address + 2).T shl 16 or
      self.readImpl(address + 1).T shl 8 or
      self.readImpl(address + 0)

func writeImpl(self: Mcu, address: MemAddress, value: uint8) =
  let
    handler = self.findHandler(address)
  handler.write(address, value)

func write*[T: uint8 | uint16 | uint32](self: Mcu, address: MemAddress, value: T) =
  # TODO: only works on little endian architectures
  when T is uint8:
    self.writeImpl(address, value)
  elif T is uint16:
    self.writeImpl(address + 0, value.uint8)
    self.writeImpl(address + 1, (value shr 8).uint8)
  elif T is uint32:
    self.writeImpl(address + 0, value.uint8)
    self.writeImpl(address + 1, (value shr 8).uint8)
    self.writeImpl(address + 2, (value shr 16).uint8)
    self.writeImpl(address + 3, (value shr 24).uint8)

func `[]`*(self: Mcu, address: MemAddress): uint8 =
  self.read[:uint8](address)

func `[]=`*(self: Mcu, address: MemAddress, value: uint8) =
  self.write(address, value)


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

proc createHandlerFor*(slot: MemSlot, values: ptr seq[uint8]): MemHandler =
  assert MemSlotSize[slot].len == values[].len
  MemHandler(
    read: proc(address: MemAddress): uint8 = values[(address - MemSlotSize[slot].a).int],
    write: proc(address: MemAddress, value: uint8) = values[(address - MemSlotSize[slot].a).int] = value,
  )

proc setHandler*(self: Mcu, slot: MemSlot, handler: MemHandler) =
  self.handlers[slot] = handler
  
proc setHandler*[T: tuple | object | array | uint8 | seq[uint8]](self: Mcu, slot: MemSlot, obj: ptr T) =
  self.setHandler(slot, createHandlerFor(slot, obj))


proc newMcu*(): Mcu =
  result = Mcu()
  result.setHandler(msDebug, NullHandler)
