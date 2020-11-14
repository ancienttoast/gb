import
  std/bitops



template wrap32*(value: int): int =
  value and 0b00011111



template `+=`*[T](self: var set[T], other: set[T]) =
  self = self + other

template `-=`*[T](self: var set[T], other: set[T]) =
  self = self - other

proc `?=`*[T](self: var set[T], value: tuple[doInclude: bool, other: set[T]]) =
  if value.doInclude:
    self +=  value.other
  else:
    self -= value.other



# Required for older gcc versions wich don't yet support the built-in endian swapping
# functions used by std/endians. E.g: the gcc version used by the psp devkit
when defined(useSoftwareEndianSwap) or defined(js):
  proc swapEndian16(value: uint16): uint16 =
    (value shr 8) or (value shl 8 )

  proc swapEndian32(value: uint32): uint32 =
    ((value shr 24) and 0xff) or
      ((value shl 8) and 0xff0000) or
      ((value shr 8) and 0xff00) or
      ((value shl 24) and 0xff000000'u32)

  when system.cpuEndian == bigEndian:
    proc littleEndian*[T: uint16 | uint32](value: T): T =
      when T is uint16:
        swapEndian16(value)
      elif T is uint32:
        swapEndian32(value)
      elif T is uint64:
        value
    
    proc bigEndian*[T: uint16 | uint32 | uint64](value: T): T =
      value
  else:
    proc littleEndian*[T: uint16 | uint32 | uint64](value: T): T =
      value
    
    proc bigEndian*[T: uint16 | uint32](value: T): T =
      when T is uint16:
        swapEndian16(value)
      elif T is uint32:
        swapEndian32(value)
      elif T is uint64:
        value
else:
  import std/endians

  proc littleEndian*[T: uint16 | uint32 | uint64](value: T): T =
    when T is uint16:
      littleEndian16(addr result, unsafeAddr value)
    elif T is uint32:
      littleEndian32(addr result, unsafeAddr value)
    elif T is uint64:
      littleEndian64(addr result, unsafeAddr value)

  proc bigEndian*[T: uint16 | uint32 | uint64](value: T): T =
    when T is uint16:
      bigEndian16(addr result, unsafeAddr value)
    elif T is uint32:
      bigEndian32(addr result, unsafeAddr value)
    elif T is uint64:
      bigEndian64(addr result, unsafeAddr value)



export testBit, setBit

func setBit*[T: uint8 | uint16 | int](value: var T, bit: static[int]) =
  const
    Mask = 1.T shl bit
  value = value or Mask

func getBit*[T: uint8 | uint16 | int](value: T, bit: int): T =
  (value shr bit) and 0b00000001

func clearBit*[T: uint8 | uint16 | uint32 | int](value: var T, bit: static[int]) =
  const
    Mask = 1.T shl bit
  value = value and not Mask

func testBit*[T: uint8 | uint16 | int](value: T, bit: static[int]): bool =
  const
    Mask = 1.T shl bit
  (value and Mask) == Mask

func setBits*[T: uint8 | uint16](bits: Slice[int]): T =
  for b in bits:
    result = result or (1.T shl b.T)

func toggleBit*[T: uint8 | uint16](value: var T, bit: static[int], bitValue: bool) =
  if bitValue:
    value.setBit(bit)
  else:
    value.clearBit(bit)


iterator count*[T](slice: Slice[T]): int =
  if slice.a < slice.b:
    for i in slice: yield i
  else:
    for i in countdown(slice.a, slice.b): yield i
