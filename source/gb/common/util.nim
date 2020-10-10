##
## `https://stackoverflow.com/a/776523`_
##
import
  std/[bitops, math]



template wrap32*(value: int): int =
  value and 0b00011111



template `+=`*[T](self: var set[T], other: set[T]) =
  self = self + other

template `-=`*[T](self: var set[T], other: set[T]) =
  self = self - other

proc `?=`*[T](self: var set[T], value: tuple[doInclude: bool, other: set[T]]) =
  ## Adds the contents of `other` to `self` if `doInclude`is true.
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
  ## Sets `bit` in `value` to 1.
  ## 
  ## The mask to achieve this is computed at compile time so at runtime it
  ## should only be a sinple `or`.
  const
    Mask = 1.T shl bit
  value = value or Mask

func getBit*[T: uint8 | uint16 | int](value: T, bit: int): T =
  (value shr bit) and 0b00000001

func clearBit*[T: uint8 | uint16 | uint32 | int](value: var T, bit: static[int]) =
  ## Sets `bit` in `value` to 0.
  ## 
  ## The mask to achieve this is computed at compile time so at runtime it
  ## should only be a sinple `or`.
  const
    Mask = 1.T shl bit
  value = value and not Mask

func testBit*[T: uint8 | uint16 | int](value: T, bit: static[int]): bool =
  ## Returns the value of `bit` as a boolean.
  const
    Mask = 1.T shl bit
  (value and Mask) == Mask

func setBits*[T: uint8 | uint16](bits: Slice[int]): T =
  ## Sets every bit in `bits` to 1.
  for b in bits:
    result = result or (1.T shl b.T)

func toggleBit*[T: uint8 | uint16](value: var T, bit: static[int], bitValue: bool) =
  ## Sets `bit` to `bitValue`.
  if bitValue:
    value.setBit(bit)
  else:
    value.clearBit(bit)

func extract*[T: uint8 | uint16 | uint32](value: T, a, b: static[int]): T =
  ## Extracts bits between `a` and `b`. `a` has to be equal or smaller then `b`.
  static:
    assert a <= b
  const
    bits = a..b
    Mask = (2^bits.len - 1).T
  (value shr bits.a) and Mask


iterator count*[T](slice: Slice[T]): int =
  if slice.a < slice.b:
    for i in slice: yield i
  else:
    for i in countdown(slice.a, slice.b): yield i


func signExtend*[T](x: T, bits: static[int]): T =
  const
    m = (1 shl (bits - 1)).T
  (x xor m) - m





func extract*[T: uint16 | uint32](value: T, a, b: static[int]): T =
  const
    bits = a..b
    Mask = (2^bits.len - 1).T
  (value shr bits.a) and Mask

func rotateLeft*[T: uint16 | uint32](x: T, n: uint): T =
  # Based on: https://blog.regehr.org/archives/1063
  (x shl n) or (x shr (32 - n))

func rotateRight*[T: uint16 | uint32](x: T, n: uint): T =
  # Based on: https://blog.regehr.org/archives/1063
  (x shr n) or (x shl (32 - n))

func ashr*[T: int32](x: T, n: uint): T =
  ## Only works for two's complement
  ## TODO: I think n == 0 undefined
  if x < 0:
    not(not x shr n)
  else:
    x shr n

func `ashr`*[T: uint32](x: T, n: uint): T =
  cast[uint32](ashr(cast[int32](x), n))