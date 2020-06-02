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



proc swapEndian64*(outp, inp: pointer) =
    ## copies `inp` to `outp` swapping bytes. Both buffers are supposed to
    ## contain at least 8 bytes.
    var i = cast[cstring](inp)
    var o = cast[cstring](outp)
    o[0] = i[7]
    o[1] = i[6]
    o[2] = i[5]
    o[3] = i[4]
    o[4] = i[3]
    o[5] = i[2]
    o[6] = i[1]
    o[7] = i[0]

proc swapEndian32*(outp, inp: pointer) =
  ## copies `inp` to `outp` swapping bytes. Both buffers are supposed to
  ## contain at least 4 bytes.
  var i = cast[cstring](inp)
  var o = cast[cstring](outp)
  o[0] = i[3]
  o[1] = i[2]
  o[2] = i[1]
  o[3] = i[0]

proc swapEndian16*(outp, inp: pointer) =
  ## copies `inp` to `outp` swapping bytes. Both buffers are supposed to
  ## contain at least 2 bytes.
  var i = cast[cstring](inp)
  var o = cast[cstring](outp)
  o[0] = i[1]
  o[1] = i[0]

when system.cpuEndian == bigEndian:
  proc littleEndian64*(outp, inp: pointer) {.inline.} = swapEndian64(outp, inp)
  proc littleEndian32*(outp, inp: pointer) {.inline.} = swapEndian32(outp, inp)
  proc littleEndian16*(outp, inp: pointer) {.inline.} = swapEndian16(outp, inp)
  proc bigEndian64*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 8)
  proc bigEndian32*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 4)
  proc bigEndian16*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 2)
else:
  proc littleEndian64*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 8)
  proc littleEndian32*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 4)
  proc littleEndian16*(outp, inp: pointer){.inline.} = copyMem(outp, inp, 2)
  proc bigEndian64*(outp, inp: pointer) {.inline.} = swapEndian64(outp, inp)
  proc bigEndian32*(outp, inp: pointer) {.inline.} = swapEndian32(outp, inp)
  proc bigEndian16*(outp, inp: pointer) {.inline.} = swapEndian16(outp, inp)

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

func setBits*[T: uint8 | uint16](bits: Slice[int]): T =
  for b in bits:
    result = result or (1.T shl b.T)


iterator count*(a, b: int): int =
  if a < b:
    for i in a..b: yield i
  else:
    for i in countdown(a, b): yield i
