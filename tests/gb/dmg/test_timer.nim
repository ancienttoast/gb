import
  std/unittest,
  gb/dmg/[mem, timer]



suite "unit.dmg.timer: Timer - divider":
  test "autoincrement":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    timer.step(256)
    check mcu[0xff04] == 1
    check timer.state.divider == 1
  
  test "overflow":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    timer.step(256*256)
    check mcu[0xff04] == 0
    check timer.state.divider == 0
  
  test "reset":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    timer.step(256)
    mcu[0xff04] = 100'u8
    check mcu[0xff04] == 0
    check timer.state.divider == 0


suite "unit.dmg.timer: Timer - TIMA":
  test "autoincrement - freq 00":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000100'u8
    timer.step(1024)
    check mcu[0xff05] == 1
    check timer.state.tima == 1

  test "autoincrement - freq 01":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000101'u8
    timer.step(16)
    check mcu[0xff05] == 1
    check timer.state.tima == 1
  
  test "autoincrement - freq 10":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000110'u8
    timer.step(64)
    check mcu[0xff05] == 1
    check timer.state.tima == 1
  
  test "autoincrement - freq 11":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000111'u8
    timer.step(256)
    check mcu[0xff05] == 1
    check timer.state.tima == 1
  
  test "overflow":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000101'u8
    mcu[0xff06] = 20'u8
    timer.step(16*256)
    check mcu[0xff05] == 20
    check timer.state.tima == 20
  
  test "write":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff05] = 20'u8
    check mcu[0xff05] == 20
    check timer.state.tima == 20
  
  test "disable":
    var
      mcu = newMcu()
      timer = newTimer(mcu)
    mcu[0xff07] = 0b00000001'u8
    timer.step(16)
    check mcu[0xff05] == 0
    check timer.state.tima == 0
