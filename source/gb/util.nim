import
  std/[endians, bitops]



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



proc littleEndian*(value: uint16): uint16 =
  littleEndian16(addr result, unsafeAddr value)

proc bigEndian*(value: uint16): uint16 =
  bigEndian16(addr result, unsafeAddr value)



export testBit

func setBit*[T: uint8 | uint16 | int](value: var T, bit: static[int]) =
  const
    Mask = 1.T shl bit
  value = value or Mask

func getBit*[T: uint8 | uint16 | int](value: T, bit: int): T =
  (value shr bit) and 0b00000001

func clearBit*[T: uint8 | uint16 | int](value: var T, bit: static[int]) =
  const
    Mask = 1.T shl bit
  value = value and not Mask

func testBit*[T: uint8 | uint16 | int](value: T, bit: static[int]): bool =
  const
    Mask = 1.T shl bit
  (value and Mask) == Mask



iterator count*(a, b: int): int =
  if a < b:
    for i in a..b: yield i
  else:
    for i in countdown(a, b): yield i
