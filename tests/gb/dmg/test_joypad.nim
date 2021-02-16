import
  std/unittest,
  gb/dmg/[mem, joypad]



template joyTest(name: untyped, body: untyped) =
  test name:
    var
      mem {.inject.} = newSeq[uint8](uint16.high - 1)
      mcu {.inject.} = newMcu(addr mem)
      joy {.inject.} = newJoypad(mcu)
    body



suite "unit.dmg.joy: Joypad - Button keys mode":
  joyTest "kA":
    joy[kA] = true
    mcu[0xff00] = 0b00010000'u8
    check mcu[0xff00] == 0b0000_1110
  
  joyTest "kB":
    joy[kB] = true
    mcu[0xff00] = 0b00010000'u8
    check mcu[0xff00] == 0b0000_1101
  
  joyTest "kSelect":
    joy[kSelect] = true
    mcu[0xff00] = 0b00010000'u8
    check mcu[0xff00] == 0b0000_1011
  
  joyTest "kStart":
    joy[kStart] = true
    mcu[0xff00] = 0b00010000'u8
    check mcu[0xff00] == 0b0000_0111
  
  joyTest "kRight":
    joy[kRight] = true
    mcu[0xff00] = 0b00010000'u8
    check mcu[0xff00] == 0b0000_1111
  
  joyTest "kLeft":
    joy[kLeft] = true
    mcu[0xff00] = 0b00010000'u8
    check mcu[0xff00] == 0b0000_1111
  
  joyTest "kUp":
    joy[kUp] = true
    mcu[0xff00] = 0b00010000'u8
    check mcu[0xff00] == 0b0000_1111
  
  joyTest "kDown":
    joy[kDown] = true
    mcu[0xff00] = 0b00010000'u8
    check mcu[0xff00] == 0b0000_1111


suite "unit.dmg.joy: Joypad - Direction keys mode":
  joyTest "kA":
    joy[kA] = true
    mcu[0xff00] = 0b00100000'u8
    check mcu[0xff00] == 0b0000_1111
  
  joyTest "kB":
    joy[kB] = true
    mcu[0xff00] = 0b00100000'u8
    check mcu[0xff00] == 0b0000_1111
  
  joyTest "kSelect":
    joy[kSelect] = true
    mcu[0xff00] = 0b00100000'u8
    check mcu[0xff00] == 0b0000_1111
  
  joyTest "kStart":
    joy[kStart] = true
    mcu[0xff00] = 0b00100000'u8
    check mcu[0xff00] == 0b0000_1111
  
  joyTest "kRight":
    joy[kRight] = true
    mcu[0xff00] = 0b00100000'u8
    check mcu[0xff00] == 0b0000_1110
  
  joyTest "kLeft":
    joy[kLeft] = true
    mcu[0xff00] = 0b00100000'u8
    check mcu[0xff00] == 0b0000_1101
  
  joyTest "kUp":
    joy[kUp] = true
    mcu[0xff00] = 0b00100000'u8
    check mcu[0xff00] == 0b0000_1011
  
  joyTest "kDown":
    joy[kDown] = true
    mcu[0xff00] = 0b00100000'u8
    check mcu[0xff00] == 0b0000_0111