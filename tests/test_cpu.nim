import
  std/[unittest, strformat],
  gb/[mem, cpu]



template cpuTest(name: untyped, body: untyped) =
  test name:
    var
      mem {.inject.} = newSeq[uint8](8)
      mcu {.inject.} = newMcu(addr mem)
      cpu {.inject.} = newCpu(mcu)
    body
    step(cpu, mcu)
    check cpu.state == oldS
    check mem == oldM


template modState(cpu: SM83, body: untyped): CpuState =
  var
    s {.inject.} = cpu.state
  body
  s

template modMem(mem: seq[uint8], body: untyped): seq[uint8] =
  var
    m {.inject.} = mem.deepCopy
  body
  m

template modMem(mem: seq[uint8]): seq[uint8] =
  mem.deepCopy



suite "LR35902 - Misc/control instructions":
  cpuTest "NOP":
    mem[0] = 0x00'u8
    let
      oldS = cpu.modState:
        s.pc += 1
      oldM = mem.modMem


suite "LR35902 - Jumps/calls":
  cpuTest "RET":
    cpu.state.sp = 6
    mem[0] = 0xc9'u8
    mem[7] = 0'u8
    mem[6] = 5'u8
    let
      oldS = cpu.modState:
        s.pc = 5
        s.sp = 8
      oldM = mem.modMem


suite "LR35902 - 8bit load/store/move instructions":
  cpuTest "LD B,d8":
    mem[0] = 0x06'u8
    mem[1] = 5'u8
    let
      oldS = cpu.modState:
        s.pc += 2
        s[rB] = 5
      oldM = mem.modMem


suite "LR35902 - 16bit arithmetic/logical instructions":
  cpuTest "ADD HL,DE":
    mem[0] = 0x19'u8
    cpu.state[rHL] = 1
    cpu.state[rDE] = 2
    let
      oldS = cpu.modState:
        s.pc += 1
        s[rHL] = 3
      oldM = mem.modMem
  
  cpuTest "ADD HL,SP":
    mem[0] = 0x39'u8
    cpu.state[rHL] = 1
    cpu.state.sp = 2
    let
      oldS = cpu.modState:
        s.pc += 1
        s[rHL] = 3
      oldM = mem.modMem


suite "LR35902 - 8bit arithmetic/logical instructions":
  cpuTest "DEC r8 - 10":
    mem[0] = 0x05'u8
    cpu.state[rB] = 10
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fAddSub }
        s[rB] = 9
      oldM = mem.modMem
  
  cpuTest "DEC r8 - 0":
    mem[0] = 0x05'u8
    cpu.state[rB] = 0
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fAddSub }
        s[rB] = 255
      oldM = mem.modMem
  
  cpuTest "OR r8 - non 0":
    mem[0] = 0xb2'u8
    cpu.state[rA] = 0b00001111
    cpu.state[rD] = 0b10101010
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { }
        s[rA] = 0b10101111
      oldM = mem.modMem
  
  cpuTest "OR r8 - 0":
    mem[0] = 0xb2'u8
    cpu.state[rA] = 0b00000000
    cpu.state[rD] = 0b00000000
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fZero }
        s[rA] = 0b00000000
      oldM = mem.modMem
  
  cpuTest "OR (HL)":
    mem[0] = 0xb6'u8
    mem[1] = 0b10101010'u8
    cpu.state[rA] = 0b00001111
    cpu.state[rHL] = 1
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { }
        s[rA] = 0b10101111
      oldM = mem.modMem
  
  cpuTest "OR A":
    mem[0] = 0xb7'u8
    cpu.state[rA] = 0b00001111
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { }
        s[rA] = 0b00001111
      oldM = mem.modMem
  
  cpuTest "CPL":
    mem[0] = 0x2f'u8
    cpu.state[rA] = 0b10011001
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fAddSub, fHalfCarry }
        s[rA] = 0b01100110
      oldM = mem.modMem


suite "LR35902 - 8bit rotations/shifts and bit instructions":
  cpuTest "RL r8 - c=0 00000000":
    mem[0] = 0xcb
    mem[1] = 0x11
    cpu.state[rC] = 0b00000000
    cpu.state.flags = {}
    let
      oldS = cpu.modState:
        s.pc += 2
        s.flags = { fZero }
      oldM = mem.modMem

  cpuTest "RL r8 - c=0 10000000":
    mem[0] = 0xcb'u8
    mem[1] = 0x11
    cpu.state[rC] = 0b10000000
    cpu.state.flags = {}
    let
      oldS = cpu.modState:
        s.pc += 2
        s.flags = { fZero, fCarry }
        s[rC] = 0b00000000
      oldM = mem.modMem

  cpuTest "RL r8 - c=1 00000100":
    mem[0] = 0xcb'u8
    mem[1] = 0x11
    cpu.state[rC] = 0b00000100
    cpu.state.flags = { fCarry }
    let
      oldS = cpu.modState:
        s.pc += 2
        s.flags = {}
        s[rC] = 0b00001001
      oldM = mem.modMem
  
  for reg in [(rA, 0x37), (rB, 0x30), (rC, 0x31), (rD, 0x32), (rE, 0x33), (rH, 0x34), (rL, 0x35)]:
    cpuTest &"SWAP {reg[0]} - not 0":
      mem[0] = 0xcb'u8
      mem[1] = reg[1].uint8
      cpu.state[reg[0]] = 0b00010111
      let
        oldS = cpu.modState:
          s.pc += 2
          s.flags = {}
          s[reg[0]] = 0b01110001
        oldM = mem.modMem
    
    cpuTest &"SWAP {reg[0]} - 0":
      mem[0] = 0xcb'u8
      mem[1] = reg[1].uint8
      cpu.state[reg[0]] = 0b00000000
      let
        oldS = cpu.modState:
          s.pc += 2
          s.flags = { fZero }
          s[reg[0]] = 0b00000000
        oldM = mem.modMem

  for reg in [(rA, 0x87), (rB, 0x80), (rC, 0x81), (rD, 0x82), (rE, 0x83), (rH, 0x84), (rL, 0x85)]:
    cpuTest &"RES 0,{reg[0]}":
      mem[0] = 0xcb'u8
      mem[1] = reg[1].uint8
      cpu.state[reg[0]] = 0b11111111
      let
        oldS = cpu.modState:
          s.pc += 2
          s[reg[0]] = 0b11111110
        oldM = mem.modMem

  cpuTest &"RES 0,(HL)":
    mem[0] = 0xcb'u8
    mem[1] = 0x86'u8
    mem[3] = 0b11111111
    cpu.state[rHL] = 3
    let
      oldS = cpu.modState:
        s.pc += 2
      oldM = mem.modMem:
        m[3] = 0b11111110
  
  for reg in [(rA, 0xc7), (rB, 0xc0), (rC, 0xc1), (rD, 0xc2), (rE, 0xc3), (rH, 0xc4), (rL, 0xc5)]:
    cpuTest &"SET 0,{reg[0]}":
      mem[0] = 0xcb'u8
      mem[1] = reg[1].uint8
      cpu.state[reg[0]] = 0b00000000
      let
        oldS = cpu.modState:
          s.pc += 2
          s[reg[0]] = 0b00000001
        oldM = mem.modMem

  cpuTest &"SET 0,(HL)":
    mem[0] = 0xcb'u8
    mem[1] = 0xc6'u8
    mem[3] = 0b00000000
    cpu.state[rHL] = 3
    let
      oldS = cpu.modState:
        s.pc += 2
      oldM = mem.modMem:
        m[3] = 0b00000001


suite "LR35902 - combined":
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
      oldM = mem.modMem
    oldM[5] = 0x34
    oldM[6] = 0x12
    cpu.step(mcu)
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
