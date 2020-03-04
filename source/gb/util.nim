import
  std/endians



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
