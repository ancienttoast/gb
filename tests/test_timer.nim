import
  unittest,
  mem, timer



suite "Timer - divider":
  test "autoincrement":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    for i in 0..255: timer.step()
    check mcu[0xff04] == 1
  
  test "overflow":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    for i in 0..<256*256: timer.step()
    check mcu[0xff04] == 0
  
  test "reset":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    for i in 0..<256: timer.step()
    mcu[0xff04] = 100'u8
    check mcu[0xff04] == 0


suite "Timer - TIMA":
  test "autoincrement - freq 00":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000100'u8
    for i in 0..1023: timer.step()
    check mcu[0xff05] == 1

  test "autoincrement - freq 01":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000101'u8
    for i in 0..15: timer.step()
    check mcu[0xff05] == 1
  
  test "autoincrement - freq 10":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000110'u8
    for i in 0..63: timer.step()
    check mcu[0xff05] == 1
  
  test "autoincrement - freq 11":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000111'u8
    for i in 0..255: timer.step()
    check mcu[0xff05] == 1
  
  test "overflow":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000101'u8
    mcu[0xff06] = 20'u8
    for i in 0..<16*256: timer.step()
    check mcu[0xff05] == 20
  
  test "write":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff05] = 20'u8
    check mcu[0xff05] == 20
  
  test "disable":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000001'u8
    for i in 0..15: timer.step()
    check mcu[0xff05] == 0
