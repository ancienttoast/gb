##[

  Sharp LR35902

  * `https://pastraiser.com/cpu/gameboy/gameboy_opcodes.html`_
  * `https://robdor.com/2016/08/10/gameboy-emulator-half-carry-flag/`_
  * `https://stackoverflow.com/a/57981912`_
  * `https://pastraiser.com/cpu/gameboy/gameboy_opcodes.htm`_
  * `http://forums.nesdev.com/viewtopic.php?f=20&t=15944#p196282`_

]##
import
  std/[bitops, strutils, strformat, macros],
  mem, interrupt, util



const
  CpuFrequency* = 4194304 ## [Hz]

type
  InstructionInfo = tuple
    duration: int
    dissasm: string

  InstructionDefinition = object
    f: proc(opcode: uint8, cpu: var Sm83State, mem: var Mcu): InstructionInfo {.noSideEffect.}
    p: proc(opcode: uint8, cpu: var Sm83State, mem: var Mcu): string {.noSideEffect.}


  Flag* {.size: sizeof(uint8).} = enum
    fUnused0
    fUnused1
    fUnused2
    fUnused3
    fCarry      ## c - Carry flag
    fHalfCarry  ## h - Half carry flag
    fAddSub     ## n - Add/Sub-flag
    fZero       ## z - Zero flag
  
  JumpCondition = enum
    jcNZ = (0b00, "NZ") ## Z flag not set
    jcZ  = (0b01, "Z")  ## Z flag set
    jcNC = (0b10, "NC") ## C flag not set
    jcC  = (0b11, "C")  ## C flag set

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

  Sm83StatusFlag* = enum
    sfHalted
    sfInterruptWait
    sfInterruptEnable
    sfInterruptDisable

  Sm83State* = object
    r*:  array[Register8, uint8]
    sp*: uint16 ## Stack Pointer
    pc*: uint16 ## Program Counter/Pointer
    ime*: uint8
    ie*: set[Interrupt]    ## Interrupt enable (R/W)
    `if`*: set[Interrupt]  ## Interrupt flag (R/W)
    status*: set[Sm83StatusFlag]

  Sm83* = ref object
    state*: Sm83State
  
  Cpu* = Sm83
  CpuState* = Sm83State

const
  Registers*: array[Register16, array[2, Register8]] = [ [rA, rF], [rB, rC], [rD, rE], [rH, rL] ]

proc setupMemHandler*(mcu: Mcu, self: Sm83) =
  mcu.setHandler(msInterruptFlag, cast[ptr uint8](addr self.state.`if`))
  mcu.setHandler(msInterruptEnabled, cast[ptr uint8](addr self.state.ie))

proc newCpu*(mcu: Mcu): Sm83 =
  result = Sm83()
  mcu.setupMemHandler(result)


template `[]`*(self: Sm83State, register: Register8): uint8 =
  self.r[register]

template `[]=`*(self: var Sm83State, register: Register8, value: uint8) =
  self.r[register] = value

proc `[]`*(self: Sm83State, register: Register16): uint16 =
  bigEndian(cast[ptr uint16](unsafeAddr self.r[(register.ord * 2).Register8])[])

proc `[]=`*(self: var Sm83State, register: Register16, value: uint16) =
  cast[ptr uint16](addr self.r[(register.ord * 2).Register8])[] = bigEndian(value)


proc `$`*(self: Sm83State): string =
  result = "("
  for r in Register16:
    result &= &"{r}: {self[r]:#06x}, "
  result &= &"sp: {self.sp:#06x}, pc: {self.pc:#06x}, ie: {self.ie}, if: {self.`if`})"

template `$`*(self: Sm83): string =
  $self.state


proc flags*(self: Sm83State): set[Flag] =
  cast[set[Flag]](self[rF])

proc flags*(self: var Sm83State): var set[Flag] =
  cast[var set[Flag]](addr self[rF])

proc `flags=`*(self: var Sm83State, flags: set[Flag]) =
  self[rF] = cast[uint8](flags)


func readNext(self: var Sm83State, mem: Mcu): uint8 =
  result = mem[self.pc]
  self.pc += 1

func push(self: var Sm83State, mem: var Mcu, value: uint16) =
  mem[self.sp - 2] = (value and 0x00ff).uint8
  mem[self.sp - 1] = ((value and 0xff00) shr 8).uint8
  self.sp -= 2

func pop[T: uint16](self: var Sm83State, mem: var Mcu): T =
  self.sp += 2
  result = mem[self.sp - 2].uint16
  result = result or (mem[self.sp - 1].uint16 shl 8)



macro genOpName(def: untyped): untyped =
  def.expectKind({nnkProcDef, nnkIdent})
  if def.kind == nnkProcDef:
    def[0].expectKind(nnkIdent)
    def[0] = newIdentNode($def[0] & "Impl")
    def
  else:
    newIdentNode($def & "Impl")

template op(name, dur, body: untyped): untyped {.dirty.} =
  proc name(opcode: uint8, cpu: var Sm83State, mem: var Mcu): InstructionInfo {.genOpName.} =
    result.duration = dur
    #result.dissasm = "?"
    body

  const
    `name` = InstructionDefinition(
      f: genOpName(name)
    )


func test(cond: JumpCondition, cpu: var Sm83State): bool =
  case cond
  of jcNZ: fZero notin cpu.flags
  of jcZ:  fZero in cpu.flags
  of jcNC: fCarry notin cpu.flags
  of jcC:  fCarry in cpu.flags


template nn(cpu: var Sm83State, mem: var Mcu): uint16 =
  ## Order: LSB, MSB
  let
    lsb = cpu.readNext(mem).uint16
    msb = cpu.readNext(mem).uint16
  (msb shl 8) or lsb

template cc(opcode: uint8): JumpCondition =
  ((opcode and 0b00011000) shr 3).JumpCondition

template bit(opcode: uint8): range[0..7] =
  (opcode and 0b00111000) shr 3


template hasHalfCarrySub(a, b: uint8): bool =
  (a and 0x0f) < (b and 0x0f)

func hasHalfCarryAdd[T: uint8 | uint16](bits: static[int], a, b: T): bool =
  const
    mask = setBits[T](0..bits)
  (a and mask) + (b and mask) > mask

template hasHalfCarryAdd(a, b: uint8): bool =
  hasHalfCarryAdd(3, a, b)


#[ Misc ]#
op opINV, 1:
  #result.dissasm = &"Invalid opcode ({opcode:#04x})"
  discard


#[ Jumps/calls ]#
op opJPu16, 4:
  cpu.pc = cpu.nn(mem)
  #result.dissasm = &"JP {cpu.pc:#x}"

op opJPHL, 1:
  cpu.pc = cpu[rHL]
  #result.dissasm = "JP HL"

op opJPccu16, 3:
  # TODO: variable length  cc == false: 3, cc == true: 4
  let
    nn = cpu.nn(mem)
  if opcode.cc.test(cpu):
    cpu.pc = nn
  #result.dissasm = &"JP {opcode.cc},{nn:#x}"

op opJRs8, 3:
  let
    e = cast[int8](cpu.readNext(mem))
  cpu.pc = (cpu.pc.int + e.int).uint16
  #result.dissasm = &"JR {e:#x}"

op opJRccs8, 2:
  # TODO: variable length  cc == false: 2, cc == true: 3
  let
    e = cast[int8](cpu.readNext(mem))
  if opcode.cc.test(cpu):
    cpu.pc = (cpu.pc.int + e.int).uint16
  #result.dissasm = &"JR {opcode.cc},{e:#x}"

func opCall(cpu: var Sm83State, mem: var Mcu, nn: uint16) =
  cpu.push(mem, cpu.pc)
  cpu.pc = nn

op opCALLu16, 6:
  let
    nn = cpu.nn(mem)
  opCall(cpu, mem, nn)
  #result.dissasm = &"CALL {nn:#x}"

op opCALLccu16, 3:
  # TODO: variable length  cc == false: 3, cc == true: 6
  let
    nn = cpu.nn(mem)
  if opcode.cc.test(cpu):
    opCall(cpu, mem, nn)
  #result.dissasm = &"CALL {opcode.cc},{nn:#x}"

op opRET, 4:
  cpu.pc = cpu.pop[:uint16](mem)
  #result.dissasm = &"RET"

op opRETcc, 2: # 5
  if opcode.cc.test(cpu):
    cpu.pc = cpu.pop[:uint16](mem)
  #result.dissasm = &"RET {opcode.cc}"

op opRETI, 4:
  cpu.pc = cpu.pop[:uint16](mem)
  cpu.ime = 1
  #result.dissasm = "RETI"

op opRST, 4:
  const
    Address = [0x00'u16, 0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38]
  let
    rst = Address[(opcode and 0b00111000) shr 3]
  cpu.push(mem, cpu.pc)
  cpu.pc = rst
  #result.dissasm = "RST {rst:#x}"


#[ 8bit load/store/move instructions ]#
op opLDr8r8, 1:
  let
    xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
    yyy = ((opcode and 0b00000111) + 2).Register8
  cpu[xxx] = cpu[yyy]
  #result.dissasm = &"LD {xxx},{yyy}"

op opLDr8d8, 2:
  let
    xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[xxx] = cpu.readNext(mem)
  #result.dissasm = &"LD {xxx},{cpu[xxx]:#x}"

op opLDr8HL, 2:
  let
    xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[xxx] = mem[cpu[rHL]]
  #result.dissasm = &"LD {xxx},(HL)"

op opLDpHLr8, 2:
  let
    xxx = ((opcode and 0b00000111) + 2).Register8
  mem[cpu[rHL]] = cpu[xxx]
  #result.dissasm = &"LD (HL),{xxx}"

op opLDpHLA, 2:
  mem[cpu[rHL]] = cpu[rA]
  #result.dissasm = "LD (HL),A"

op opLDHLd8, 3:
  mem[cpu[rHL]] = cpu.readNext(mem)
  #result.dissasm = &"LD (HL),{mem[cpu[rHL]]:#x}"

op opLDAr8, 2:
  let
    yyy = ((opcode and 0b00000111) + 2).Register8
  cpu[rA] = cpu[yyy]
  #result.dissasm = &"LD A,{yyy}"

op opLDAA, 1:
  cpu[rA] = cpu[rA]
  #result.dissasm = "LD A,A"

op opLDr8A, 1:
  let
    xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[xxx] = cpu[rA]
  #result.dissasm = &"LD {xxx},A"

op opLDAHL, 2:
  cpu[rA] = mem[cpu[rHL]]
  #result.dissasm = "LD A,(HL)"

op opLDAu8, 2:
  cpu[rA] = cpu.readNext(mem)
  #result.dissasm = &"LD A,{cpu[rA]:#x}"

op opLDABC, 2:
  cpu[rA] = mem[cpu[rBC]]
  #result.dissasm = "LD A,(BC)"

op opLDADE, 2:
  cpu[rA] = mem[cpu[rDE]]
  #result.dissasm = "LD A,(DE)"

op opLDBCA, 2:
  mem[cpu[rBC]] = cpu[rA]
  #result.dissasm = "LD (BC),A"

op opLDDEA, 2:
  mem[cpu[rDE]] = cpu[rA]
  #result.dissasm = "LD (DE),A"

op opLDAHLp, 2:
  cpu[rA] = mem[cpu[rHL]]
  cpu[rHL] = cpu[rHL] + 1
  #result.dissasm = "LD A,(HL+)"

op opLDAHLm, 2:
  cpu[rA] = mem[cpu[rHL]]
  cpu[rHL] = cpu[rHL] - 1
  #result.dissasm = "LD A,(HL-)"

op opLDHLpA, 2:
  mem[cpu[rHL]] = cpu[rA]
  cpu[rHL] = cpu[rHL] + 1
  #result.dissasm = "LD (HL+),A"

op opLDHLmA, 2:
  mem[cpu[rHL]] = cpu[rA]
  cpu[rHL] = cpu[rHL] - 1
  #result.dissasm = "LD (HL-),A"

op opLDpCA, 2:
  ## Put A into memory at address 0xff00 + C
  mem[0xff00'u16 + cpu[rC].uint16] = cpu[rA]
  #result.dissasm = "LD (C),A"

op opLDApC, 2:
  ## Put memory value at address 0xff00 + C into A
  cpu[rA] = mem[0xff00'u16 + cpu[rC].uint16]
  #result.dissasm = "LD A,(C)"

op opLDHAu8, 3:
  ## Put memory value at address 0xff00 + u8 into A
  let
    u8 = cpu.readNext(mem)
  cpu[rA] = mem[0xff00'u16 + u8.uint16]
  #result.dissasm = &"LDH A,{u8:#x}"

op opLDHu8A, 3:
  ## Put A into memory at address 0xff00 + u8
  let
    u8 = cpu.readNext(mem)
  mem[0xff00'u16 + u8.uint16] = cpu[rA]
  #result.dissasm = &"LDH {u8:#x},A"

op opLDAu16, 4:
  let
    u16 = cpu.nn(mem)
  cpu[rA] = mem[u16]

  #result.dissasm = &"LD A,({u16:#x})"

op opLDu16A, 4:
  let
    u16 = cpu.nn(mem)
  mem[u16] = cpu[rA]
  #result.dissasm = &"LD ({u16:#x}),A"


#[ 16bit load/store/move instructions ]#
op opLDr16u16, 3:
  let
    xx = (opcode and 0b00110000) shr 4
  assert xx in {0, 1, 2, 3}, $xx
  let
    nn = cpu.nn(mem)
  if xx == 3:
    cpu.sp = nn
    #result.dissasm = &"LD SP,{nn:#x}"
  else:
    let
      r16 = (xx + 1).Register16
    cpu[r16] = nn
    #result.dissasm = &"LD {r16},{nn:#04x}"

op opLDSPHL, 2:
  cpu.sp = cpu[rHL]
  #result.dissasm = "LD SP,HL"

op opLDHLSPps8, 3:
  let
    s8 = cpu.readNext(mem)
    d8 = cast[int8](s8)
  cpu.flags ?= (hasHalfCarryAdd(7, cpu.sp, s8), { fCarry })
  cpu.flags ?= (hasHalfCarryAdd(3, cpu.sp, s8), { fHalfCarry })
  cpu[rHL] = (cpu.sp.int + d8.int).uint16
  cpu.flags -= { fZero, fAddSub }
  #result.dissasm = &"LD HL,SP+{s8:#x}"

op opLDu16SP, 5:
  let
    nn = cpu.nn(mem)
  mem[nn] = cpu.sp
  #result.dissasm = &"LD {nn:#x},SP"

op opPOPr16, 3:
  let
    xx = (opcode and 0b00110000) shr 4 + 1
  assert xx in {1, 2, 3, 4}
  let
    r16 = (if xx == 4: 0'u8 else: xx).Register16
  cpu[r16] = cpu.pop[:uint16](mem)
  if r16 == rAF:
    # zero out the lower nibble of register f since it cannot be modified
    cpu[rF] = cpu[rF] and 0b11110000
  #result.dissasm = &"POP {r16}"

op opPUSHr16, 4:
  let
    xx = ((opcode and 0b00110000) shr 4)
  assert xx in {0, 1, 2, 3}
  if xx == 3:
    cpu.push(mem, cpu[rAF])
    #result.dissasm = "PUSH AF"
  else:
    let
      r16 = (xx + 1).Register16
    cpu.push(mem, cpu[r16])
    #result.dissasm = &"PUSH {r16}"


#[ 8bit arithmetic/logical instructions ]#
func opXor(cpu: var Sm83State, value: uint8) =
  cpu[rA] = cpu[rA] xor value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry, fCarry }

op opXORr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  opXor(cpu, cpu[r8])
  #result.dissasm = &"XOR {r8}"

op opXORpHL, 2:
  opXor(cpu, mem[cpu[rHL]])
  #result.dissasm = "XOR (HL)"

op opXORA, 1:
  opXor(cpu, cpu[rA])
  #result.dissasm = "XOR A"

op opXORd8, 2:
  let
    d8 = cpu.readNext(mem)
  opXor(cpu, d8)
  #result.dissasm = &"XOR {d8}"

func opInc(cpu: var Sm83State, mem: var Mcu, value: uint8): uint8 = 
  result = value + 1
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub }
  cpu.flags ?= (hasHalfCarryAdd(value, 1), { fHalfCarry })

op opINCr8, 1:
  let
    r8 = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[r8] = cpu.opInc(mem, cpu[r8])
  #result.dissasm = &"INC {r8}"

op opINCpHL, 3:
  mem[cpu[rHL]] = cpu.opInc(mem, mem[cpu[rHL]])
  #result.dissasm = &"INC HL"

op opINCA, 1:
  cpu[rA] = cpu.opInc(mem, cpu[rA])
  #result.dissasm = &"INC A"

func opDec(cpu: var Sm83State, mem: var Mcu, value: uint8): uint8 = 
  result = value - 1
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags += { fAddSub }
  cpu.flags ?= (hasHalfCarrySub(value, 1), { fHalfCarry })

op opDECr8, 1:
  let
    r8 = (((opcode and 0b00111000) shr 3) + 2).Register8
  cpu[r8] = cpu.opDec(mem, cpu[r8])
  #result.dissasm = &"DEC {r8}"

op opDECpHL, 3:
  mem[cpu[rHL]] = cpu.opDec(mem, mem[cpu[rHL]])
  #result.dissasm = &"INC HL"

op opDECA, 1:
  cpu[rA] = cpu.opDec(mem, cpu[rA])
  #result.dissasm = &"DEC A"

func opCp(cpu: var Sm83State, value: uint8) =
  cpu.flags ?= (cpu[rA] < value, { fCarry })
  cpu.flags ?= (hasHalfCarrySub(cpu[rA], value), { fHalfCarry })
  let
    res = cpu[rA] - value
  cpu.flags ?= (res == 0, { fZero })
  cpu.flags += { fAddSub }

op opCPr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  opCp(cpu, cpu[r8])
  #result.dissasm = &"CP {r8}"

op opCPpHL, 2:
  opCp(cpu, mem[cpu[rHL]])
  #result.dissasm = &"CP (HL)"

op opCPA, 1:
  opCp(cpu, cpu[rA])
  #result.dissasm = &"CP A"

op opCPu8, 2:
  let
    u8 = cpu.readNext(mem)
  opCp(cpu, u8)
  #result.dissasm = &"CP {u8:#x}"

func opSub(cpu: var Sm83State, value: uint8) =
  cpu.flags ?= (cpu[rA] < value, { fCarry })
  cpu.flags ?= (hasHalfCarrySub(cpu[rA], value), { fHalfCarry })
  cpu[rA] = cpu[rA] - value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags += { fAddSub }

op opSUBr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  opSub(cpu, cpu[r8])
  #result.dissasm = &"SUB {r8}"

op opSUBHL, 2:
  opSub(cpu, mem[cpu[rHL]])
  #result.dissasm = "SUB (HL)"

op opSUBA, 1:
  opSub(cpu, cpu[rA])
  #result.dissasm = "SUB A"

op opSUBd8, 2:
  let
    d8 = cpu.readNext(mem)
  opSub(cpu, d8)
  #result.dissasm = &"SUB {d8}"

func opAdd(cpu: var Sm83State, value: uint8) =
  cpu.flags ?= (cpu[rA].int + value.int > uint8.high.int, { fCarry })
  cpu.flags ?= (hasHalfCarryAdd(cpu[rA], value), { fHalfCarry })
  cpu[rA] = cpu[rA] + value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub }

op opADDAr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  opAdd(cpu, cpu[r8])
  #result.dissasm = &"ADD A,{r8}"

op opADDAHL, 2:
  opAdd(cpu, mem[cpu[rHL]])
  #result.dissasm = &"ADD A,(HL)"

op opADDAA, 1:
  opAdd(cpu, cpu[rA])
  #result.dissasm = &"ADD A,A"

op opADDAd8, 2:
  let
    d8 = cpu.readNext(mem)
  opAdd(cpu, d8)
  #result.dissasm = &"ADD A,{d8}"

func opOr(cpu: var Sm83State, mem: var Mcu, value: uint8) =
  cpu[rA] = cpu[rA] or value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry, fCarry }

op opORr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  opOr(cpu, mem, cpu[r8])
  #result.dissasm = &"OR {r8}"

op opORpHL, 2:
  opOr(cpu, mem, mem[cpu[rHL]])
  #result.dissasm = &"OR (HL)"

op opORA, 1:
  opOr(cpu, mem, cpu[rA])
  #result.dissasm = &"OR A"

op opORd8, 2:
  let
    d8 = cpu.readNext(mem)
  opOr(cpu, mem, d8)
  #result.dissasm = &"OR {d8}"

op opCPL, 1:
  cpu[rA] = not cpu[rA]
  cpu.flags += { fAddSub, fHalfCarry }
  #result.dissasm = "CPL"

func opAnd(cpu: var Sm83State, mem: var Mcu, value: uint8) =
  cpu[rA] = cpu[rA] and value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags += { fHalfCarry }
  cpu.flags -= { fAddSub, fCarry }

op opANDr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  opAnd(cpu, mem, cpu[r8])
  #result.dissasm = &"AND {r8}"

op opANDpHL, 2:
  opAnd(cpu, mem, mem[cpu[rHL]])
  #result.dissasm = &"AND (HL)"

op opANDA, 1:
  opAnd(cpu, mem, cpu[rA])
  #result.dissasm = &"AND A"

op opANDd8, 2:
  let
    d8 = cpu.readNext(mem)
  opAnd(cpu, mem, d8)
  #result.dissasm = &"AND {d8}"

op opSCF, 1:
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags += { fCarry }
  #result.dissasm = &"SCF"

op opCCF, 1:
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (fCarry notin cpu.flags, { fCarry })
  #result.dissasm = &"CCF"

func opAdc(cpu: var Sm83State, value: uint8) =
  let
    carry = if fCarry in cpu.flags: 1'u8 else: 0
  cpu.flags ?= (cpu[rA].int + value.int + carry.int > 255, { fCarry })
  cpu.flags ?= (hasHalfCarryAdd(cpu[rA], value) or hasHalfCarryAdd(cpu[rA] + value, carry), { fHalfCarry })
  cpu[rA] = cpu[rA] + value + carry
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub }

op opADCr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  opAdc(cpu, cpu[r8])
  #result.dissasm = &"ADC A,{r8}"

op opADCpHL, 2:
  opAdc(cpu, mem[cpu[rHL]])
  #result.dissasm = "ADC A,(HL)"

op opADCA, 1:
  opAdc(cpu, cpu[rA])
  #result.dissasm = "ADC A,A"

op opADCd8, 1:
  let
    n = cpu.readNext(mem)
  opAdc(cpu, n)
  #result.dissasm = &"ADC A,{n}"

func opSbc(cpu: var Sm83State, value: uint8) =
  let
    carry = if fCarry in cpu.flags: 1'u8 else: 0
  cpu.flags ?= (value.int + carry.int > cpu[rA].int, { fCarry })
  cpu.flags ?= (hasHalfCarrySub(cpu[rA], value) or hasHalfCarrySub(cpu[rA] - value, carry), { fHalfCarry })
  cpu[rA] = cpu[rA] - value - carry
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags += { fAddSub }

op opSBCr8, 1:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  opSbc(cpu, cpu[r8])
  #result.dissasm = &"SDC A,{r8}"

op opSBCpHL, 2:
  opSbc(cpu, mem[cpu[rHL]])
  #result.dissasm = "SDC A,(HL)"

op opSBCA, 1:
  opSbc(cpu, cpu[rA])
  #result.dissasm = "SDC A,A"

op opSBCd8, 1:
  let
    n = cpu.readNext(mem)
  opSbc(cpu, n)
  #result.dissasm = &"SDC A,{n}"

op opDAA, 1:
  # from: http://forums.nesdev.com/viewtopic.php?f=20&t=15944#p196282
  # note: assumes a is a uint8_t and wraps from 0xff to 0
  if fAddSub notin cpu.flags:
    # after an addition, adjust if (half-)carry occurred or if result is out of bounds
    if fCarry in cpu.flags or cpu[rA] > 0x99'u8:
      cpu[rA] = cpu[rA] + 0x60
      cpu.flags += { fCarry }
    if fHalfCarry in cpu.flags or (cpu[rA] and 0x0f) > 0x09'u8:
      cpu[rA] = cpu[rA] + 0x6
  else:
    # after a subtraction, only adjust if (half-)carry occurred
    if fCarry in cpu.flags:
      cpu[rA] = cpu[rA] - 0x60
    if fHalfCarry in cpu.flags:
      cpu[rA] = cpu[rA] - 0x6

  # these flags are always updated
  cpu.flags ?= (cpu[rA] == 0, { fZero }) # the usual z flag
  cpu.flags -= { fHalfCarry } # h flag is always cleared
  #result.dissasm = "DAA"


#[ 16bit arithmetic/logical instructions ]#
op opINCr16, 2:
  let
    r16 = (((opcode and 0b00110000) shr 4) + 1).Register16
  cpu[r16] = cpu[r16] + 1
  #result.dissasm = &"INC {r16}"

op opINCSP, 2:
  cpu.sp = cpu.sp + 1
  #result.dissasm = &"INC SP"

op opDECr16, 2:
  let
    r16 = (((opcode and 0b00110000) shr 4) + 1).Register16
  cpu[r16] = cpu[r16] - 1
  #result.dissasm = &"DEC {r16}"

op opDECSP, 2:
  cpu.sp = cpu.sp - 1
  #result.dissasm = &"DEC SP"

func opAddHl(cpu: var Sm83State, value: uint16) =
  cpu.flags ?= (cpu[rHL] > uint16.high - value, { fCarry })
  cpu.flags ?= (hasHalfCarryAdd(11, cpu[rHL], value), { fHalfCarry })
  cpu[rHL] = cpu[rHL] + value
  cpu.flags -= { fAddSub }

op opADDHLr16, 2:
  let
    r16 = (((opcode and 0b00110000) shr 4) + 1).Register16
  opAddHl(cpu, cpu[r16])
  #result.dissasm = &"ADD HL,{r16}"

op opADDHLSP, 2:
  opAddHl(cpu, cpu.sp)
  #result.dissasm = "ADD HL,SP"

op opADDSPs8, 2:
  let
    s8 = cpu.readNext(mem)
    d8 = cast[int8](s8)
  cpu.flags ?= (hasHalfCarryAdd(7, cpu.sp, s8), { fCarry })
  cpu.flags ?= (hasHalfCarryAdd(3, cpu.sp, s8), { fHalfCarry })
  cpu.sp = (cpu.sp.int + d8.int).uint16
  cpu.flags -= { fZero, fAddSub }
  #result.dissasm = &"ADD SP,{s8}"


#[ 8bit rotations/shifts and bit instructions ]#
func opRlc(cpu: var Sm83State, value: uint8): uint8 =
  let
    carry = (value and 0b10000000) shr 7
  result = (value shl 1) or carry
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })

op opRLCr8, 2:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opRlc(cpu, cpu[r8])
  #result.dissasm = &"RLC {r8}"

op opRLCpHL, 4:
  mem[cpu[rHL]] = opRlc(cpu, mem[cpu[rHL]])
  #result.dissasm = &"RLC (HL)"

op opRLCA, 1:
  cpu[rA] = opRlc(cpu, cpu[rA])
  cpu.flags -= { fZero }
  #result.dissasm = &"RLC A"

op opCBRLCA, 2:
  cpu[rA] = opRlc(cpu, cpu[rA])
  #result.dissasm = &"RLC A"

func opRl(cpu: var Sm83State, value: uint8): uint8 =
  let
    carry = (value and 0b10000000) shr 7
  result = value shl 1
  if fCarry in cpu.flags:
    result = result or 1
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })

op opRLr8, 2:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opRl(cpu, cpu[r8])
  #result.dissasm = &"RL {r8}"

op opRLpHL, 4:
  mem[cpu[rHL]] = opRl(cpu, mem[cpu[rHL]])
  #result.dissasm = &"RL (HL)"

op opRLA, 1:
  cpu[rA] = opRl(cpu, cpu[rA])
  cpu.flags -= { fZero }
  #result.dissasm = &"RL A"

op opCBRLA, 2:
  cpu[rA] = opRl(cpu, cpu[rA])
  #result.dissasm = &"RL A"

func opSla(cpu: var Sm83State, value: uint8): uint8 =
  let
    carry = (value and 0b10000000) shr 7
  result = value shl 1
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })

op opSLAr8, 2:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opSla(cpu, cpu[r8])
  #result.dissasm = &"SLA {r8}"

op opSLApHL, 4:
  mem[cpu[rHL]] = opSla(cpu, mem[cpu[rHL]])
  #result.dissasm = &"SLA (HL)"

op opSLAA, 2:
  cpu[rA] = opSla(cpu, cpu[rA])
  #result.dissasm = &"SLA A"

func opBit(cpu: var Sm83State, bit: range[0..7], value: uint8) =
  cpu.flags ?= (not testBit(value, bit.int), { fZero })
  cpu.flags -= { fAddSub }
  cpu.flags += { fHalfCarry }

op opBITr8, 2:
  let
    bit = opcode.bit
    r8 = ((opcode and 0b00000111) + 2).Register8
  opBit(cpu, bit, cpu[r8])
  #result.dissasm = &"BIT {bit},{r8}"

op opBITpHL, 4:
  let
    bit = opcode.bit
  opBit(cpu, bit, mem[cpu[rHL]])
  #result.dissasm = &"BIT {bit},(HL)"

op opBITA, 2:
  let
    bit = opcode.bit
  opBit(cpu, bit, cpu[rA])
  #result.dissasm = &"BIT {bit},A"

func opSet(bit: range[0..7], value: uint8): uint8 =
  result = value
  setBit[uint8](result, bit)

op opSETbr8, 2:
  let
    bit = opcode.bit
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opSet(bit, cpu[r8])
  #result.dissasm = &"SET {bit},{r8}"

op opSETbpHL, 2:
  let
    bit = opcode.bit
  mem[cpu[rHL]] = opSet(bit, mem[cpu[rHL]])
  #result.dissasm = &"SET {bit},(HL)"

op opSETbA, 2:
  let
    bit = opcode.bit
  cpu[rA] = opSet(bit, cpu[rA])
  #result.dissasm = &"SET {bit},A"

func opRes(bit: range[0..7], value: uint8): uint8 =
  result = value
  clearBit[uint8](result, bit)

op opRESbr8, 2:
  let
    bit = opcode.bit
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opRes(bit, cpu[r8])
  #result.dissasm = &"RES {bit},{r8}"

op opRESbpHL, 2:
  let
    bit = opcode.bit
  mem[cpu[rHL]] = opRes(bit, mem[cpu[rHL]])
  #result.dissasm = &"RES {bit},(HL)"

op opRESbA, 2:
  let
    bit = opcode.bit
  cpu[rA] = opRes(bit, cpu[rA])
  #result.dissasm = &"RES {bit},A"

func opSwap(cpu: var Sm83State, value: uint8): uint8 =
  result = ((value and 0x0f) shl 4) or ((value and 0xf0) shr 4)
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry, fCarry }

op opSWAPr8, 2:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opSwap(cpu, cpu[r8])
  #result.dissasm = &"SWAP {r8}"

op opSWAPpHL, 4:
  mem[cpu[rHL]] = opSwap(cpu, mem[cpu[rHL]])
  #result.dissasm = &"SWAP (HL)"

op opSWAPA, 2:
  cpu[rA] = opSwap(cpu, cpu[rA])
  #result.dissasm = &"SWAP A"

func opRrc(cpu: var Sm83State, value: uint8): uint8 =
  let
    carry = (value and 0b00000001) == 1
  result = value shr 1
  if carry:
    result = result or 0b10000000
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry, { fCarry })

op opRRCr8, 2:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opRrc(cpu, cpu[r8])
  #result.dissasm = &"RRC {r8}"

op opRRCpHL, 4:
  mem[cpu[rHL]] = opRrc(cpu, mem[cpu[rHL]])
  #result.dissasm = &"RRC (HL)"

op opRRCA, 1:
  cpu[rA] = opRrc(cpu, cpu[rA])
  cpu.flags -= { fZero }
  #result.dissasm = &"RRC A"

op opCBRRCA, 2:
  cpu[rA] = opRrc(cpu, cpu[rA])
  #result.dissasm = &"RRC A"

func opRr(cpu: var Sm83State, value: uint8): uint8 =
  let
    carry = (value and 0b00000001) == 1
  result = value shr 1
  if fCarry in cpu.flags:
    result = result or 0b10000000
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry, { fCarry })

op opRRr8, 2:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opRr(cpu, cpu[r8])
  #result.dissasm = &"RR {r8}"

op opRRpHL, 4:
  mem[cpu[rHL]] = opRr(cpu, mem[cpu[rHL]])
  #result.dissasm = &"RR (HL)"

op opRRA, 1:
  cpu[rA] = opRr(cpu, cpu[rA])
  cpu.flags -= { fZero }
  #result.dissasm = &"RR A"

op opCBRRA, 2:
  cpu[rA] = opRr(cpu, cpu[rA])
  #result.dissasm = &"RR A"

func opSra(cpu: var Sm83State, value: uint8): uint8 =
  let
    msb = value and 0b10000000
    carry = value and 0b00000001
  result = (value shr 1) or msb
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })

op opSRAr8, 2:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opSra(cpu, cpu[r8])
  #result.dissasm = &"SRA {r8}"

op opSRApHL, 4:
  mem[cpu[rHL]] = opSra(cpu, mem[cpu[rHL]])
  #result.dissasm = &"SRA (HL)"

op opSRAA, 2:
  cpu[rA] = opSra(cpu, cpu[rA])
  #result.dissasm = &"SRA A"

func opSrl(cpu: var Sm83State, value: uint8): uint8 =
  let
    carry = value and 0b00000001
  result = value shr 1
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })

op opSRLr8, 2:
  let
    r8 = ((opcode and 0b00000111) + 2).Register8
  cpu[r8] = opSrl(cpu, cpu[r8])
  #result.dissasm = &"SRL {r8}"

op opSRLpHL, 4:
  mem[cpu[rHL]] = opSrl(cpu, mem[cpu[rHL]])
  #result.dissasm = &"SRL (HL)"

op opSRLA, 2:
  cpu[rA] = opSrl(cpu, cpu[rA])
  #result.dissasm = &"SRL A"


const
  PrefixCbTable: array[256, InstructionDefinition] = [
    opRLCr8,   opRLCr8,   opRLCr8,   opRLCr8,   opRLCr8,   opRLCr8,   opRLCpHL,  opCBRLCA,  opRRCr8,   opRRCr8,   opRRCr8,   opRRCr8,   opRRCr8,   opRRCr8,   opRRCpHL,  opCBRRCA,
    opRLr8,    opRLr8,    opRLr8,    opRLr8,    opRLr8,    opRLr8,    opRLpHL,   opCBRLA,   opRRr8,    opRRr8,    opRRr8,    opRRr8,    opRRr8,    opRRr8,    opRRpHL,   opCBRRA,
    opSLAr8,   opSLAr8,   opSLAr8,   opSLAr8,   opSLAr8,   opSLAr8,   opSLApHL,  opSLAA,    opSRAr8,   opSRAr8,   opSRAr8,   opSRAr8,   opSRAr8,   opSRAr8,   opSRApHL,  opSRAA,
    opSWAPr8,  opSWAPr8,  opSWAPr8,  opSWAPr8,  opSWAPr8,  opSWAPr8,  opSWAPpHL, opSWAPA,   opSRLr8,   opSRLr8,   opSRLr8,   opSRLr8,   opSRLr8,   opSRLr8,   opSRLpHL,  opSRLA,
    opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITpHL,  opBITA,    opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITpHL,  opBITA,
    opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITpHL,  opBITA,    opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITpHL,  opBITA,
    opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITpHL,  opBITA,    opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITpHL,  opBITA,
    opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITpHL,  opBITA,    opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITr8,   opBITpHL,  opBITA,
    opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbpHL, opRESbA,   opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbpHL, opRESbA,
    opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbpHL, opRESbA,   opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbpHL, opRESbA,
    opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbpHL, opRESbA,   opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbpHL, opRESbA,
    opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbpHL, opRESbA,   opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbr8,  opRESbpHL, opRESbA,
    opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbpHL, opSETbA,   opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbpHL, opSETbA,
    opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbpHL, opSETbA,   opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbpHL, opSETbA,
    opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbpHL, opSETbA,   opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbpHL, opSETbA,
    opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbpHL, opSETbA,   opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbr8,  opSETbpHL, opSETbA,
  ]


#[ Misc/control instructions ]#
op opNOP, 1:
  #result.dissasm = "NOP"
  discard

op opSTOP, 1:
  # TODO
  #result.dissasm = "STOP"
  discard

op opHALT, 1:
  cpu.status += { sfHalted }
  #result.dissasm = "HALT"

op opPreCB, 1:
  let
    opcode = cpu.readNext(mem)
    instruction = PrefixCbTable[opcode.int]
  instruction.f(opcode, cpu, mem)

op opDI, 1:
  ## Disable interrupt handling (ime = 0) after the next instruction
  cpu.status += { sfInterruptWait, sfInterruptDisable }
  #result.dissasm = "DI"

op opEI, 1:
  ## Enable interrupt handling (ime = 1) after the next instruction
  cpu.status += { sfInterruptWait, sfInterruptEnable }
  #result.dissasm = "EI"

const
  OpcodeTable: array[256, InstructionDefinition] = [
    opNOP,     opLDr16u16, opLDBCA,   opINCr16,  opINCr8,     opDECr8,   opLDr8d8, opRLCA,   opLDu16SP,   opADDHLr16, opLDABC,   opDECr16, opINCr8,     opDECr8,   opLDr8d8, opRRCA,
    opSTOP,    opLDr16u16, opLDDEA,   opINCr16,  opINCr8,     opDECr8,   opLDr8d8, opRLA,    opJRs8,      opADDHLr16, opLDADE,   opDECr16, opINCr8,     opDECr8,   opLDr8d8, opRRA,
    opJRccs8,  opLDr16u16, opLDHLpA,  opINCr16,  opINCr8,     opDECr8,   opLDr8d8, opDAA,    opJRccs8,    opADDHLr16, opLDAHLp,  opDECr16, opINCr8,     opDECr8,   opLDr8d8, opCPL,
    opJRccs8,  opLDr16u16, opLDHLmA,  opINCSP,   opINCpHL,    opDECpHL,  opLDHLd8, opSCF,    opJRccs8,    opADDHLSP,  opLDAHLm,  opDECSP,  opINCA,      opDECA,    opLDAu8,  opCCF,
    opLDr8r8,  opLDr8r8,   opLDr8r8,  opLDr8r8,  opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A,  opLDr8r8,    opLDr8r8,   opLDr8r8,  opLDr8r8, opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A,
    opLDr8r8,  opLDr8r8,   opLDr8r8,  opLDr8r8,  opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A,  opLDr8r8,    opLDr8r8,   opLDr8r8,  opLDr8r8, opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A,
    opLDr8r8,  opLDr8r8,   opLDr8r8,  opLDr8r8,  opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A,  opLDr8r8,    opLDr8r8,   opLDr8r8,  opLDr8r8, opLDr8r8,    opLDr8r8,  opLDr8HL, opLDr8A,
    opLDpHLr8, opLDpHLr8,  opLDpHLr8, opLDpHLr8, opLDpHLr8,   opLDpHLr8, opHALT,   opLDpHLA, opLDAr8,     opLDAr8,    opLDAr8,   opLDAr8,  opLDAr8,     opLDAr8,   opLDAHL,  opLDAA,
    opADDAr8,  opADDAr8,   opADDAr8,  opADDAr8,  opADDAr8,    opADDAr8,  opADDAHL, opADDAA,  opADCr8,     opADCr8,    opADCr8,   opADCr8,  opADCr8,     opADCr8,   opADCpHL, opADCA,
    opSUBr8,   opSUBr8,    opSUBr8,   opSUBr8,   opSUBr8,     opSUBr8,   opSUBHL,  opSUBA,   opSBCr8,     opSBCr8,    opSBCr8,   opSBCr8,  opSBCr8,     opSBCr8,   opSBCpHL, opSBCA,
    opANDr8,   opANDr8,    opANDr8,   opANDr8,   opANDr8,     opANDr8,   opANDpHL, opANDA,   opXORr8,     opXORr8,    opXORr8,   opXORr8,  opXORr8,     opXORr8,   opXORpHL, opXORA,
    opORr8,    opORr8,     opORr8,    opORr8,    opORr8,      opORr8,    opORpHL,  opORA,    opCPr8,      opCPr8,     opCPr8,    opCPr8,   opCPr8,      opCPr8,    opCPpHL,  opCPA,
    opRETcc,   opPOPr16,   opJPccu16, opJPu16,   opCALLccu16, opPUSHr16, opADDAd8, opRST,    opRETcc,     opRET,      opJPccu16, opPreCB,  opCALLccu16, opCALLu16, opADCd8,  opRST,
    opRETcc,   opPOPr16,   opJPccu16, opINV,     opCALLccu16, opPUSHr16, opSUBd8,  opRST,    opRETcc,     opRETI,     opJPccu16, opINV,    opCALLccu16, opINV,     opSBCd8,    opRST,
    opLDHu8A,  opPOPr16,   opLDpCA,   opINV,     opINV,       opPUSHr16, opANDd8,  opRST,    opADDSPs8,   opJPHL,     opLDu16A,  opINV,    opINV,       opINV,     opXORd8,  opRST,
    opLDHAu8,  opPOPr16,   opLDApC,   opDI,      opINV,       opPUSHr16, opORd8,   opRST,    opLDHLSPps8, opLDSPHL,   opLDAu16,  opEI,     opINV,       opINV,     opCPu8,   opRST
  ]


func step*(self: var Sm83, mem: var Mcu): int {.discardable.} =
  if self.state.`if` != {}:
    self.state.status -= { sfHalted }
    if self.state.ime == 1:
      for interrupt in Interrupt:
        if interrupt in self.state.ie and interrupt in self.state.`if`:
          self.state.ime = 0
          self.state.`if` -= { interrupt }
          opCall(self.state, mem, InterruptHandler[interrupt])
          return 5

  if sfHalted in self.state.status:
    return 1

  let
    opcode = self.state.readNext(mem)
    instruction = OpcodeTable[opcode.int]
  let
    (cycles, _) = instruction.f(opcode, self.state, mem)

  if sfInterruptWait notin self.state.status:
    if sfInterruptEnable in self.state.status:
      self.state.ime = 1
      self.state.status -= { sfInterruptEnable }
    
    if sfInterruptDisable in self.state.status:
      self.state.ime = 0
      self.state.status -= { sfInterruptDisable }
  else:
    self.state.status -= { sfInterruptWait }

  cycles * 4
