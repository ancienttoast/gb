import
  std/unittest,
  gb/gba/mem

suite "unit.gba.mem: Memory Bus":
  test "read 8bit":
    var
      data = newSeq[uint8](16_384)
    let
      mcu = newMcu()
    mcu.setHandler(msBios, addr data)
    data[0] = 0x0a
    data[1] = 0x0b
    data[2] = 0x0c
    data[3] = 0x0d

    check mcu.read[:uint8](0) == 0x0a
    check mcu.read[:uint8](1) == 0x0b
    check mcu.read[:uint8](2) == 0x0c
    check mcu.read[:uint8](3) == 0x0d
  
  test "read 16bit":
    var
      data = newSeq[uint8](16_384)
    let
      mcu = newMcu()
    mcu.setHandler(msBios, addr data)
    data[0] = 0x0d
    data[1] = 0x0c
    data[2] = 0x0b
    data[3] = 0x0a

    check mcu.read[:uint16](0) == 0x0c0d
    check mcu.read[:uint16](1) == 0x0b0c
    check mcu.read[:uint16](2) == 0x0a0b
  
  test "read 32bit":
    var
      data = newSeq[uint8](16_384)
    let
      mcu = newMcu()
    mcu.setHandler(msBios, addr data)
    data[0] = 0x0d
    data[1] = 0x0c
    data[2] = 0x0b
    data[3] = 0x0a

    check mcu.read[:uint32](0) == 0x0a0b0c0d
  
  test "write 8bit":
    var
      data = newSeq[uint8](16_384)
    let
      mcu = newMcu()
    mcu.setHandler(msBios, addr data)

    mcu.write[:uint8](0, 0x0a)
    check data[0] == 0x0a
  
  test "write 16bit":
    var
      data = newSeq[uint8](16_384)
    let
      mcu = newMcu()
    mcu.setHandler(msBios, addr data)

    mcu.write[:uint16](0, 0x0a0b'u16)
    check data[0] == 0x0b
    check data[1] == 0x0a
  
  test "write 32bit":
    var
      data = newSeq[uint8](16_384)
    let
      mcu = newMcu()
    mcu.setHandler(msBios, addr data)

    mcu.write[:uint32](0, 0x0a0b0c0d'u32)
    check data[0] == 0x0d
    check data[1] == 0x0c
    check data[2] == 0x0b
    check data[3] == 0x0a
  
  test "write and read 8bit":
    var
      data = newSeq[uint8](16_384)
    let
      mcu = newMcu()
    mcu.setHandler(msBios, addr data)

    mcu.write[:uint8](0, 0x0a'u8)
    check mcu.read[:uint8](0) == 0x0a'u8
  
  test "write and read 16bit":
    var
      data = newSeq[uint8](16_384)
    let
      mcu = newMcu()
    mcu.setHandler(msBios, addr data)

    mcu.write[:uint16](0, 0x0a0b'u16)
    check mcu.read[:uint16](0) == 0x0a0b'u16
  
  test "write and read 32bit":
    var
      data = newSeq[uint8](16_384)
    let
      mcu = newMcu()
    mcu.setHandler(msBios, addr data)

    mcu.write[:uint32](0, 0x0a0b0c0d'u32)
    check mcu.read[:uint32](0) == 0x0a0b0c0d'u32
