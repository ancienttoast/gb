import
  unittest,
  gb/[mem, cpu]



template modState(cpu: SM83, body: untyped): CpuState =
  var
    s {.inject.} = cpu.state
  body
  s



suite "LR35902 - Misc/control instructions":
  test "NOP":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0x00'u8
    let
      st = cpu.modState:
        s.pc += 1
      oldM = mem
    cpu.step(mcu)
    check cpu.state == st
    check mem == oldM


suite "LR35902 - Jumps/calls":
  test "RET":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    cpu.state.sp = 6
    mem[0] = 0xc9'u8
    mem[7] = 0'u8
    mem[6] = 5'u8
    let
      oldS = cpu.modState:
        s.pc = 5
        s.sp = 8
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM


suite "LR35902 - 8bit load/store/move instructions":
  test "LD B,d8":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0x06'u8
    mem[1] = 5'u8
    let
      oldS = cpu.modState:
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
      cpu = newCpu(mcu)
    mem[0] = 0x05'u8
    cpu.state[rB] = 10
    let
      oldS = cpu.modState:
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
      cpu = newCpu(mcu)
    mem[0] = 0x05'u8
    cpu.state[rB] = 0
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fAddSub }
        s[rB] = 255
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
  
  test "OR r8 - non 0":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0xb2'u8
    cpu.state[rA] = 0b00001111
    cpu.state[rD] = 0b10101010
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { }
        s[rA] = 0b10101111
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
  
  test "OR r8 - 0":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0xb2'u8
    cpu.state[rA] = 0b00000000
    cpu.state[rD] = 0b00000000
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fZero }
        s[rA] = 0b00000000
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
  
  test "OR (HL)":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0xb6'u8
    mem[1] = 0b10101010'u8
    cpu.state[rA] = 0b00001111
    cpu.state[rHL] = 1
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { }
        s[rA] = 0b10101111
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
  
  test "OR A":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0xb7'u8
    cpu.state[rA] = 0b00001111
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { }
        s[rA] = 0b00001111
      oldM = mem
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM


suite "LR35902 - 8bit rotations/shifts and bit instructions":
  test "RL r8 - c=0 00000000":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0xcb'u8
    mem[1] = 0x11'u8
    cpu.state[rC] = 0b00000000
    cpu.state.flags = {}
    let
      oldS = cpu.modState:
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
      cpu = newCpu(mcu)
    mem[0] = 0xcb'u8
    mem[1] = 0x11'u8
    cpu.state[rC] = 0b10000000
    cpu.state.flags = {}
    let
      oldS = cpu.modState:
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
      cpu = newCpu(mcu)
    mem[0] = 0xcb'u8
    mem[1] = 0x11'u8
    cpu.state[rC] = 0b00000100
    cpu.state.flags = { fCarry }
    let
      oldS = cpu.modState:
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
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    cpu.state[rBC] = 0x1234

    check cpu.state[rB] == 0x12
    check cpu.state[rC] == 0x34

  test "PUSH POP":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0xc5'u8
    mem[1] = 0xe1'u8
    cpu.state[rBC] = 0x1234
    cpu.state.sp = 7
    let
      oldS = cpu.modState:
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
