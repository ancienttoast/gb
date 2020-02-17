##[

  Sharp LR35902

  * `https://robdor.com/2016/08/10/gameboy-emulator-half-carry-flag/`_
  * `https://pastraiser.com/cpu/gameboy/gameboy_opcodes.htm`_

]##
import
  std/[bitops, strutils, strformat],
  mem, util



const
  CpuFrequency* = 4194304 ## [Hz]

type
  InstructionInfo = tuple
    duration: int
    dissasm: string

  InstructionDefinition = object
    f: proc(opcode: uint8, cpu: var Sm83, mem: var Mcu): InstructionInfo {.noSideEffect.}


  Flag* {.size: sizeof(uint8).} = enum
    fUnused0
    fUnused1
    fUnused2
    fUnused3
    fCarry      ## cy - Carry flag
    fHalfCarry  ## h  - Half carry flag
    fAddSub     ## n  - Add/Sub-flag
    fZero       ## zf - Zero flag
  
  JumpCondition = enum
    jcNZ = (0b00, "NZ") # Z flag not set
    jcZ  = (0b01, "Z")  # Z flag set
    jcNC = (0b10, "NC") # C flag not set
    jcC  = (0b11, "C")  # C flag set

  Register8* = enum
    rA = (0, "A"),
    rF = (1, "F"), ## Accumulator & Flags
    rB = (2, "B"),
    rC = (3, "C"),
    rD = (4, "D"),
    rE = (5, "E"),
    rH = (6, "H"),
    rL = (7, "L")
  
  Register16* = enum
    rAF = (0, "AF")
    rBC = (1, "BC")
    rDE = (2, "DE")
    rHL = (3, "HL")

  Register = Register8 | Register16

  Sm83* = object
    r*:  array[Register8, uint8]
    sp*: uint16 ## Stack Pointer
    pc*: uint16 ## Program Counter/Pointer
  
  Cpu* = Sm83
  CpuState* = Sm83


proc initCpu*(): Sm83 =
  Sm83(
    # TODO: default values
  )

proc state*(self: Sm83): CpuState =
  self


template `[]`*(self: Sm83, register: Register8): uint8 =
  self.r[register]

template `[]=`*(self: var Sm83, register: Register8, value: uint8) =
  self.r[register] = value

proc `[]`*(self: Sm83, register: Register16): uint16 =
  # TODO: this should reverse the byte order (e.g.: DE -> this will be treated as little endian, ie ED)
  bigEndian(cast[ptr uint16](unsafeAddr self.r[(register.ord * 2).Register8])[])

proc `[]=`*(self: var Sm83, register: Register16, value: uint16) =
  # TODO: same as above
  cast[ptr uint16](addr self.r[(register.ord * 2).Register8])[] = bigEndian(value)


proc `$`*(self: Sm83): string =
  result = "("
  for r in Register16:
    result &= &"{r}: {self[r]:#06x}, "
  result &= &"sp: {self.sp}, pc: {self.pc:#06x})"


proc flags*(self: Sm83): set[Flag] =
  cast[set[Flag]](self[rF])

proc flags*(self: var Sm83): var set[Flag] =
  cast[var set[Flag]](addr self[rF])

proc `flags=`*(self: var Sm83, flags: set[Flag]) =
  self[rF] = cast[uint8](flags)


func readNext(self: var Sm83, mem: Mcu): uint8 =
  result = mem[self.pc]
  self.pc += 1

func push(self: var Sm83, mem: var Mcu, value: uint16) =
  mem[self.sp - 2] = (value and 0x00ff).uint8
  mem[self.sp - 1] = ((value and 0xff00) shr 8).uint8
  self.sp -= 2

func pop[T: uint16](self: var Sm83, mem: var Mcu): T =
  self.sp += 2
  result = mem[self.sp - 2].uint16
  result = result or (mem[self.sp - 1].uint16 shl 8)


template op(name, dur, body: untyped): untyped {.dirty.} =
  const
    `name` = InstructionDefinition(
      f: proc(opcode: uint8, cpu: var Sm83, mem: var Mcu): InstructionInfo =
        result.duration = dur
        result.dissasm = "?"
        body
    )


template nn(cpu: var Sm83, mem: var Mcu): uint16 =
  ## Order: LSB, MSB
  let
    lsb = cpu.readNext(mem).uint16
    msb = cpu.readNext(mem).uint16
  (msb shl 8) or lsb


#[ Misc ]#
op opERR, 1:
  raise newException(Exception, "Not implemented opcode: " & opcode.int.toHex(2))

op opINV, 1:
  raise newException(Exception, "Invalid opcode")


#[ Jumps/calls ]#
op opJPu16, 4:
  cpu.pc = cpu.nn(mem)
  result.dissasm = &"JP {cpu.pc:#x}"

op opJPHL, 1:
  cpu.pc = cpu[rHL]
  result.dissasm = "JP HL"

op opJPccu16, 3:
  # TODO: variable length  cc == false: 3, cc == true: 4
  let
    nn = cpu.nn(mem)
    cc = ((opcode and 0b00011000) shr 3).JumpCondition
    cond = case cc
      of jcNZ: fZero notin cpu.flags
      of jcZ:  fZero in cpu.flags
      of jcNC: fCarry notin cpu.flags
      of jcC:  fCarry in cpu.flags
  if cond:
    cpu.pc = nn
  result.dissasm = &"JP {cc},{nn:#x}"

op opJRs8, 3:
  let
    e = cast[int8](cpu.readNext(mem))
  cpu.pc = (cpu.pc.int + e.int).uint16
  result.dissasm = &"JR {e:#x}"

op opJRccs8, 2:
  # TODO: variable length  cc == false: 2, cc == true: 3
  let
    e = cast[int8](cpu.readNext(mem))
    cc = ((opcode and 0b00011000) shr 3).JumpCondition
    cond = case cc
      of jcNZ: fZero notin cpu.flags
      of jcZ:  fZero in cpu.flags
      of jcNC: fCarry notin cpu.flags
      of jcC:  fCarry in cpu.flags
  if cond:
    cpu.pc = (cpu.pc.int + e.int).uint16
  result.dissasm = &"JR {cc},{e:#x}"

op opCALLu16, 6:
  let
    nn = cpu.nn(mem)
  cpu.push(mem, cpu.pc)
  cpu.pc = nn
  result.dissasm = &"CALL {nn:#x}"

op opCALLccu16, 3:
  # TODO: variable length  cc == false: 3, cc == true: 6
  let
    nn = cpu.nn(mem)
    cc = ((opcode and 0b00011000) shr 3).JumpCondition
    cond = case cc
      of jcNZ: fZero notin cpu.flags
      of jcZ:  fZero in cpu.flags
      of jcNC: fCarry notin cpu.flags
      of jcC:  fCarry in cpu.flags
  if cond:
    cpu.push(mem, cpu.pc)
    cpu.pc = nn
  result.dissasm = &"CALL {cc},{nn:#x}"

op opRET, 4:
  cpu.pc = cpu.pop[:uint16](mem)
  result.dissasm = &"RET"


#[ 8bit load/store/move instructions ]#
op opLDr8r8, 1:
  let
    xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
    yyy = ((opcode and 0b00000111) + 2).Register8
  cpu[xxx] = cpu[yyy]
  result.dissasm = &"LD {xxx},{yyy}"

op opLDr8d8, 2:
  let
    xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[xxx] = cpu.readNext(mem)
  result.dissasm = &"LD {xxx},{cpu[xxx]:#x}"

op opLDr8HL, 2:
  let
    xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[xxx] = mem[cpu[rHL]]
  result.dissasm = &"LD {xxx},(HL)"

op opLDHLr8, 2:
  let
    xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
  mem[cpu[rHL]] = cpu[xxx]
  result.dissasm = &"LD (HL),{xxx}"

op opLDHLd8, 3:
  mem[cpu[rHL]] = cpu.readNext(mem)
  result.dissasm = &"LD (HL),{mem[cpu[rHL]]:#x}"

op opLDAr8, 2:
  let
    yyy = ((opcode and 0b00000111) + 2).Register8
  cpu[rA] = cpu[yyy]
  result.dissasm = &"LD A,{yyy}"

op opLDAA, 1:
  cpu[rA] = cpu[rA]
  result.dissasm = "LD A,A"

op opLDr8A, 1:
  let
    xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[xxx] = cpu[rA]
  result.dissasm = &"LD {xxx},A"

op opLDHLA, 2:
  mem[cpu[rHL]] = cpu[rA]
  result.dissasm = "LD (HL),A"

op opLDAHL, 2:
  cpu[rA] = mem[cpu[rHL]]
  result.dissasm = "LD A,(HL)"

op opLDAu8, 2:
  cpu[rA] = cpu.readNext(mem)
  result.dissasm = &"LD A,{cpu[rA]:#x}"

op opLDABC, 2:
  cpu[rA] = mem[cpu[rBC]]
  result.dissasm = "LD A,(BC)"

op opLDADE, 2:
  cpu[rA] = mem[cpu[rDE]]
  result.dissasm = "LD A,(DE)"

op opLDBCA, 2:
  mem[cpu[rBC]] = cpu[rA]
  result.dissasm = "LD (BC),A"

op opLDDEA, 2:
  mem[cpu[rDE]] = cpu[rA]
  result.dissasm = "LD (DE),A"

op opLDAHLp, 2:
  cpu[rA] = mem[cpu[rHL]]
  cpu[rHL] = cpu[rHL] + 1
  result.dissasm = "LD A,(HL+)"

op opLDAHLm, 2:
  cpu[rA] = mem[cpu[rHL]]
  cpu[rHL] = cpu[rHL] - 1
  result.dissasm = "LD A,(HL-)"

op opLDHLpA, 2:
  mem[cpu[rHL]] = cpu[rA]
  cpu[rHL] = cpu[rHL] + 1
  result.dissasm = "LD (HL+),A"

op opLDHLmA, 2:
  mem[cpu[rHL]] = cpu[rA]
  cpu[rHL] = cpu[rHL] - 1
  result.dissasm = "LD (HL-),A"

op opLDCA, 2:
  ## Put A into memory at address 0xff00 + C
  mem[0xff00'u16 + cpu[rC].uint16] = cpu[rA]
  result.dissasm = "LD (C),A"

op opLDAC, 2:
  ## Put memory value at address 0xff00 + C into A
  cpu[rA] = mem[0xff00'u16 + cpu[rC].uint16]
  result.dissasm = "LD A,(C)"

op opLDHAu8, 3:
  ## Put A into memory at address 0xff00 + u8
  let
    u8 = cpu.readNext(mem)
  cpu[rA] = mem[0xff00'u16 + u8.uint16]
  result.dissasm = &"LDH A,{u8:#x}"

op opLDHu8A, 3:
  ## Put memory value at address 0xff00 + u8 into A
  let
    u8 = cpu.readNext(mem)
  mem[0xff00'u16 + u8.uint16] = cpu[rA]
  result.dissasm = &"LDH {u8:#x},A"

op opLDAu16, 4:
  ## Put A into memory at address 0xff00 + u16
  let
    u16 = cpu.nn(mem)
  cpu[rA] = mem[0xff00'u16 + u16]
  result.dissasm = &"LD A,{u16:#x}"

op opLDu16A, 4:
  ## Put memory value at address 0xff00 + u16 into A
  let
    u16 = cpu.nn(mem)
  mem[0xff00'u16 + u16] = cpu[rA]
  result.dissasm = &"LD {u16:#x},A"


#[ 16bit load/store/move instructions ]#
op opLDr16u16, 3:
  let
    xx = (opcode and 0b00110000) shr 4
  assert xx in {0, 1, 2, 3}, $xx
  let
    nn = cpu.nn(mem)
  if xx == 3:
    cpu.sp = nn
    result.dissasm = &"LD SP,{nn:#x}"
  else:
    let
      r16 = (xx + 1).Register16
    cpu[r16] = nn
    result.dissasm = &"LD {r16},{nn:#04x}"

op opLDSPHL, 2:
  cpu.sp = cpu[rHL]
  result.dissasm = "LD SP,HL"

op opLDHLSPps8, 3:
  let
    s8 = cast[int8](cpu.readNext(mem))
  cpu[rHL] = (cpu.sp.int + s8).uint16
  # TODO: flags
  result.dissasm = &"LD HL,SP+{s8:#x}"

op opLDu16SP, 5:
  let
    nn = cpu.nn(mem)
  mem[nn] = cpu.sp
  result.dissasm = &"LD {nn:#x},SP"

op opPOPr16, 3:
  let
    xx = (opcode and 0b00110000) shr 4
  assert xx in {0, 1, 2, 3}
  if xx == 3:
    cpu[rAF] = cpu.pop[:uint16](mem)
    # TODO: ?flags?
    result.dissasm = "POP AF"
  else:
    let
      r16 = (xx + 1).Register16
    cpu[r16] = cpu.pop[:uint16](mem)
    result.dissasm = &"POP {r16}"

op opPUSHr16, 4:
  let
    xx = ((opcode and 0b00110000) shr 4)
  assert xx in {0, 1, 2, 3}
  if xx == 3:
    cpu.push(mem, cpu[rAF])
    result.dissasm = "PUSH A"
  else:
    let
      r16 = (xx + 1).Register16
    cpu.push(mem, cpu[r16])
    result.dissasm = &"PUSH {r16}"


#[ 8bit arithmetic/logical instructions ]#
op opXORr8, 1:
  let
    r8 = (opcode and 0b00000111) + 2
  cpu[rA] = cpu[rA] xor cpu[r8.Register8]
  # TODO: flags
  result.dissasm = &"XOR {r8.Register8}"

op opXORA, 1:
  cpu[rA] = cpu[rA] xor cpu[rA]
  # TODO: flags
  result.dissasm = "XOR A"

op opINCr8, 1:
  let
    r8 = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[r8] = cpu[r8] + 1
  # TODO: flags
  result.dissasm = &"INC {r8}"

op opINCHL, 3:
  cpu[rHL] = cpu[rHL] + 1
  # TODO: flags
  result.dissasm = &"INC HL"

op opDECr8, 1:
  let
    r8 = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[r8] = cpu[r8] - 1
  cpu.flags ?= (cpu[r8] == 0, { fZero })
  cpu.flags += { fAddSub }
  # TODO: cpu.f.incl(fHalfCarry)
  result.dissasm = &"DEC {r8}"

op opDECA, 1:
  cpu[rA] = cpu[rA] - 1
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags += { fAddSub }
  # TODO: cpu.f.incl(fHalfCarry)
  result.dissasm = &"DEC A"

op opCPr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
    res = cpu[rA] - cpu[r8]
  cpu.flags ?= (res == 0, { fZero })
  cpu.flags += { fAddSub }
  # TODO: cpu.f.incl(fHalfCarry)
  cpu.flags ?= (cpu[rA] < cpu[r8], { fCarry })
  result.dissasm = &"CP {r8}"

op opCPHL, 2:
  let
    res = cpu[rA].uint16 - mem[cpu[rHL]]
  cpu.flags ?= (res == 0, { fZero })
  cpu.flags += { fAddSub }
  # TODO: cpu.f.incl(fHalfCarry)
  cpu.flags ?= (cpu[rA].uint16 < cpu[rHL], { fCarry })
  result.dissasm = &"CP HL"

op opCPu8, 2:
  let
    u8 = cpu.readNext(mem)
    res = cpu[rA] - u8
  cpu.flags ?= (res == 0, { fZero })
  cpu.flags += { fAddSub }
  # TODO: cpu.f.incl(fHalfCarry)
  cpu.flags ?= (cpu[rA] < u8, { fCarry })
  result.dissasm = &"CP {u8:#x}"

func sub(cpu: var Sm83, mem: var Mcu, value: uint8) =
  cpu[rA] = cpu[rA] - value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags += { fAddSub }
  # TODO: cpu.f.incl(fHalfCarry)
  cpu.flags ?= (cpu[rA] < cpu[rA], { fCarry })

op opSUBr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  sub(cpu, mem, cpu[r8])
  result.dissasm = &"SUB {r8}"

op opSUBA, 1:
  sub(cpu, mem, cpu[rA])
  result.dissasm = "SUB A"

op opSUBHL, 2:
  sub(cpu, mem, mem[cpu[rHL]])
  result.dissasm = "SUB (HL)"

op opSUBu8, 2:
  let
    u8 = cpu.readNext(mem)
  sub(cpu, mem, u8)
  result.dissasm = "SUB (HL)"

func add(cpu: var Sm83, mem: var Mcu, value: uint8) =
  cpu[rA] = cpu[rA] + value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub }
  # TODO: cpu.f.incl(fHalfCarry)
  # TODO: cpu.f.incl(fCarry)

op opADDAr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  add(cpu, mem, cpu[r8])
  result.dissasm = &"ADD A,{r8}"

op opADDAA, 1:
  add(cpu, mem, cpu[rA])
  result.dissasm = &"ADD A,A"

op opADDAHL, 2:
  add(cpu, mem, mem[cpu[rHL]])
  result.dissasm = &"ADD A,(HL)"


#[ 16bit arithmetic/logical instructions ]#
op opINCr16, 2:
  let
    r16 = (((opcode and 0b00110000) shr 4) + 1).Register16
  cpu[r16] = cpu[r16] + 1
  result.dissasm = &"INC {r16}"


#[ 8bit rotations/shifts and bit instructions ]#
op opBITr8, 2:
  let
    bit = (opcode and 0b01110000) shr 4
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu.flags ?= (not testBit(cpu[r8], bit), { fZero })
  cpu.flags -= { fAddSub }
  cpu.flags += { fHalfCarry }
  result.dissasm = &"BIT {r8}"

op opRLr8, 2:
  # c=1, r8=00000000 - 00000001 c=0 z=0
  # c=0, r8=00000000 - 00000000 c=0 z=1
  # c=0, r8=10000000 - 00000000 c=1 z=1
  # B1010101 -> 1010101c c=B z=isNull n=0 h=0
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
    carry = (cpu[r8] and 0b10000000) shr 7
  cpu[r8] = cpu[r8] shl 1
  if fCarry in cpu.flags:
    cpu[r8] = cpu[r8] or 1
  cpu.flags ?= (cpu[r8] == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })
  result.dissasm = &"RL {r8}"

op opRLA, 1:
  let
    carry = (cpu[rA] and 0b10000000) shr 7
  cpu[rA] = cpu[rA] shl 1
  if fCarry in cpu.flags:
    cpu[rA] = cpu[rA] or 1
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })
  result.dissasm = "RL A"


const
  PrefixCbTable: array[256, InstructionDefinition] = [
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opRLr8,   opRLr8,     opRLr8,    opRLr8,   opRLr8,      opRLr8,    opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opBITr8,  opBITr8,    opBITr8,   opBITr8,  opBITr8,     opBITr8,   opERR,    opERR,   opBITr8,     opBITr8,  opBITr8,   opBITr8,  opBITr8,     opBITr8,   opERR,    opERR,
    opBITr8,  opBITr8,    opBITr8,   opBITr8,  opBITr8,     opBITr8,   opERR,    opERR,   opBITr8,     opBITr8,  opBITr8,   opBITr8,  opBITr8,     opBITr8,   opERR,    opERR,
    opBITr8,  opBITr8,    opBITr8,   opBITr8,  opBITr8,     opBITr8,   opERR,    opERR,   opBITr8,     opBITr8,  opBITr8,   opBITr8,  opBITr8,     opBITr8,   opERR,    opERR,
    opBITr8,  opBITr8,    opBITr8,   opBITr8,  opBITr8,     opBITr8,   opERR,    opERR,   opBITr8,     opBITr8,  opBITr8,   opBITr8,  opBITr8,     opBITr8,   opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
  ]


#[ Misc/control instructions ]#
op opNOP, 1:
  result.dissasm = "NOP"

op opSTOP, 1:
  # TODO
  result.dissasm = "STOP"

op opDI, 1:
  # TODO
  result.dissasm = "DI"

op opHALT, 1:
  # TODO
  result.dissasm = "HALT"

op opPreCB, 1:
  let
    opcode = cpu.readNext(mem)
    instruction = PrefixCbTable[opcode.int]
  instruction.f(opcode, cpu, mem)

op opEI, 1:
  # TODO
  result.dissasm = "EI"

const
  OpcodeTable: array[256, InstructionDefinition] = [ 
    opNOP,    opLDr16u16, opLDBCA,   opINCr16, opINCr8,     opDECr8,   opLDr8d8, opERR,   opLDu16SP,   opERR,    opLDABC,   opERR,    opINCr8,     opDECr8,   opLDr8d8, opERR,
    opSTOP,   opLDr16u16, opLDDEA,   opINCr16, opINCr8,     opDECr8,   opLDr8d8, opRLA,   opJRs8,      opERR,    opLDADE,   opERR,    opINCr8,     opDECr8,   opLDr8d8, opERR,
    opJRccs8, opLDr16u16, opLDHLpA,  opINCr16, opINCr8,     opDECr8,   opLDr8d8, opERR,   opJRccs8,    opERR,    opLDAHLp,  opERR,    opINCr8,     opDECr8,   opLDr8d8, opERR,
    opJRccs8, opLDr16u16, opLDHLmA,  opERR,    opINCHL,     opERR,     opLDHLd8, opERR,   opJRccs8,    opERR,    opLDAHLm,  opERR,    opERR,       opDECA,    opLDAu8,  opERR,
    opLDr8r8, opLDr8r8,   opLDr8r8,  opLDr8r8, opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A, opLDr8r8,    opLDr8r8, opLDr8r8,  opLDr8r8, opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A,
    opLDr8r8, opLDr8r8,   opLDr8r8,  opLDr8r8, opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A, opLDr8r8,    opLDr8r8, opLDr8r8,  opLDr8r8, opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A,
    opLDr8r8, opLDr8r8,   opLDr8r8,  opLDr8r8, opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A, opLDr8r8,    opLDr8r8, opLDr8r8,  opLDr8r8, opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A,
    opLDHLr8, opLDHLr8,   opLDHLr8,  opLDHLr8, opLDHLr8,    opLDHLr8,  opHALT,   opLDHLA, opLDAr8,     opLDAr8,  opLDAr8,   opLDAr8,  opLDAr8,     opLDAr8,   opLDAHL,  opLDAA,
    opADDAr8, opADDAr8,   opADDAr8,  opADDAr8, opADDAr8,    opADDAr8,  opADDAHL, opADDAA, opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opSUBr8,  opSUBr8,    opSUBr8,   opSUBr8,  opSUBr8,     opSUBr8,   opSUBHL,  opSUBA,  opERR,       opERR,    opERR,     opERR,    opERR,       opERR,     opERR,    opERR,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opXORr8,     opXORr8,  opXORr8,   opXORr8,  opXORr8,     opXORr8,   opERR,    opXORA,
    opERR,    opERR,      opERR,     opERR,    opERR,       opERR,     opERR,    opERR,   opCPr8,      opCPr8,   opCPr8,    opCPr8,   opCPr8,      opCPr8,    opCPHL,   opERR,
    opERR,    opPOPr16,   opJPccu16, opJPu16,  opCALLccu16, opPUSHr16, opERR,    opERR,   opERR,       opRET,    opJPccu16, opPreCB,  opCALLccu16, opCALLu16, opERR,    opERR,
    opERR,    opPOPr16,   opJPccu16, opINV,    opCALLccu16, opPUSHr16, opSUBu8,  opERR,   opERR,       opERR,    opJPccu16, opINV,    opCALLccu16, opINV,     opERR,    opERR,
    opLDHu8A, opPOPr16,   opLDCA,    opINV,    opINV,       opPUSHr16, opERR,    opERR,   opERR,       opJPHL,   opLDu16A,  opINV,    opINV,       opINV,     opERR,    opERR,
    opLDHAu8, opPOPr16,   opLDAC,    opDI,     opINV,       opPUSHr16, opERR,    opERR,   opLDHLSPps8, opLDSPHL, opLDAu16,  opEI,     opINV,       opINV,     opCPu8,   opERR
  ]


func step*(self: var Sm83, mem: var Mcu) =
  let
    position = self.pc
    opcode = self.readNext(mem)
    instruction = OpcodeTable[opcode.int]
  let
    (_, dissams) = instruction.f(opcode, self, mem)
  debugEcho &"{position:#06x}  {dissams:<20}{self.state}"
