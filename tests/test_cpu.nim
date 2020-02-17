import
  unittest,
  mem, cpu



template state(cpu: SM83, body: untyped): CpuState =
  var
    s {.inject.} = cpu.state
  body
  s



suite "LR35902 - Misc/control instructions":
  test "NOP":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = initCpu()
    mem[0] = 0x00'u8
    let
      st = cpu.state:
        s.pc += 1
      oldM = mem
    cpu.step(mcu)
    check cpu.state == st
    check mem == oldM


suite "LR35902 - Jumps/calls":
  # TODO
  discard


suite "LR35902 - 8bit load/store/move instructions":
  test "LD B,d8":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = initCpu()
    mem[0] = 0x06'u8
    mem[1] = 5'u8
    let
      oldS = cpu.state:
        s.pc += 2
        s[rB] = 5
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM


suite "LR35902 - 8bit arithmetic/logical instructions":
  test "DEC r8 - 10":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = initCpu()
    mem[0] = 0x05'u8
    cpu[rB] = 10
    let
      oldS = cpu.state:
        s.pc += 1
        s.flags = { fAddSub }
        s[rB] = 9
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
  
  test "DEC r8 - 0":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = initCpu()
    mem[0] = 0x05'u8
    cpu[rB] = 0
    let
      oldS = cpu.state:
        s.pc += 1
        s.flags = { fAddSub }
        s[rB] = 255
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM


suite "LR35902 - 8bit rotations/shifts and bit instructions":
  test "RL r8 - c=0 00000000":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = initCpu()
    mem[0] = 0xcb'u8
    mem[1] = 0x11'u8
    cpu[rC] = 0b00000000
    cpu.flags = {}
    let
      oldS = cpu.state:
        s.pc += 2
        s.flags = { fZero }
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
  
  test "RL r8 - c=0 10000000":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = initCpu()
    mem[0] = 0xcb'u8
    mem[1] = 0x11'u8
    cpu[rC] = 0b10000000
    cpu.flags = {}
    let
      oldS = cpu.state:
        s.pc += 2
        s.flags = { fZero, fCarry }
        s[rC] = 0b00000000
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
  
  test "RL r8 - c=1 00000100":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = initCpu()
    mem[0] = 0xcb'u8
    mem[1] = 0x11'u8
    cpu[rC] = 0b00000100
    cpu.flags = { fCarry }
    let
      oldS = cpu.state:
        s.pc += 2
        s.flags = {}
        s[rC] = 0b00001001
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM


suite "Stuff":
  test "set 16bit register":
    var
      cpu = initCpu()
    cpu[rBC] = 0x1234

    check cpu[rB] == 0x12
    check cpu[rC] == 0x34

  test "PUSH POP":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = initCpu()
    mem[0] = 0xc5'u8
    mem[1] = 0xe1'u8
    cpu[rBC] = 0x1234
    cpu.sp = 7
    let
      oldS = cpu.state:
        s.pc += 2
        s[rHL] = 0x1234
    var
      oldM = mem
    oldM[5] = 0x34
    oldM[6] = 0x12
    cpu.step(mcu)
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
