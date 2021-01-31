##[

CPU - Sharp LR35902
===================

Sources
-------

* `<https://pastraiser.com/cpu/gameboy/gameboy_opcodes.html>`_
* `<https://robdor.com/2016/08/10/gameboy-emulator-half-carry-flag/>`_
* `<https://stackoverflow.com/a/57981912>`_
* `<http://forums.nesdev.com/viewtopic.php?f=20&t=15944#p196282>`_

]##
import
  std/[bitops, strformat, macros],
  gb/common/util,
  mem, interrupt



const
  CpuFrequency* = 4194304 ## [Hz]

type
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
    sfStopped
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
  (cast[ptr set[Flag]](addr self[rF]))[]

proc `flags=`*(self: var Sm83State, flags: set[Flag]) =
  self[rF] = cast[uint8](flags)


type
  InstructionDefinition = tuple
    exec: proc(opcode: uint8, mem: var Mcu, pc: var uint16, cpu: var Sm83State): int {.noSideEffect, nimcall.}
    diss: proc(opcode: uint8, mem: var Mcu, pc: var uint16): string {.noSideEffect, nimcall.}

proc newConstDef(name: NimNode, value: NimNode): NimNode =
  result = newNimNode(nnkConstDef)
  result &= name
  result &= newEmptyNode()
  result &= value

proc newPragma(values: varargs[string]): NimNode =
  result = newNimNode(nnkPragma)
  for value in values:
    result &= newIdentNode(value)

proc newLambda(params: NimNode, pragma: NimNode, body: NimNode): NimNode =
  result = newNimNode(nnkLambda)
  result &= newEmptyNode()
  result &= newEmptyNode()
  result &= newEmptyNode()
  result &= params
  result &= pragma
  result &= newEmptyNode()
  result &= body

proc newVarTy(typ: string): NimNode =
  result = newNimNode(nnkVarTy)
  result &= newIdentNode(typ)

proc findSection(body: NimNode, section: string): NimNode =
  for child in body:
    if child.kind == nnkCall and child[0].kind == nnkIdent:
      if $child[0] == section:
        return child[1]
  return newStmtList()

macro op(name: untyped, cycles: int, body: untyped): untyped =
  expectKind(body, nnkStmtList)
  let
    decode = body.findSection("decode")
    execute = body.findSection("execute")
    print = body.findSection("print")
  
  let
    exec =
      block:
        let
          params = newNimNode(nnkFormalParams)
        params &= newIdentNode("int")
        params &= newIdentDefs(newIdentNode("opcode"), newIdentNode("uint8"), newEmptyNode())
        params &= newIdentDefs(newIdentNode("mem"), newVarTy("Mcu"), newEmptyNode())
        params &= newIdentDefs(newIdentNode("pc"), newVarTy("uint16"), newEmptyNode())
        params &= newIdentDefs(newIdentNode("cpu"), newVarTy("Sm83State"), newEmptyNode())

        let
          stmtLst = newNimNode(nnkStmtList)
        decode.copyChildrenTo(stmtLst)
        stmtLst &= newAssignment(newIdentNode("result"), cycles)
        execute.copyChildrenTo(stmtLst)
        let
          lmb = newLambda(params, newPragma("noSideEffect"), stmtLst)
        
        newColonExpr(newIdentNode("exec"), lmb)
    diss =
      block:
        let
          params = newNimNode(nnkFormalParams)
        params &= newIdentNode("string")
        params &= newIdentDefs(newIdentNode("opcode"), newIdentNode("uint8"), newEmptyNode())
        params &= newIdentDefs(newIdentNode("mem"), newVarTy("Mcu"), newEmptyNode())
        params &= newIdentDefs(newIdentNode("pc"), newVarTy("uint16"), newEmptyNode())

        let
          stmtLst = newNimNode(nnkStmtList)
        decode.copyChildrenTo(stmtLst)
        print.copyChildrenTo(stmtLst)

        let
          lmb = newLambda(params, newPragma("noSideEffect"), stmtLst)
        
        newColonExpr(newIdentNode("diss"), lmb)

  result = newNimNode(nnkConstSection)
  result &= newConstDef(name, newPar(exec, diss))


func readNext(mem: Mcu, pc: var uint16): uint8 =
  result = mem[pc]
  pc += 1

func push(self: var Sm83State, mem: var Mcu, value: uint16) =
  mem[self.sp - 2] = (value and 0x00ff).uint8
  mem[self.sp - 1] = ((value and 0xff00) shr 8).uint8
  self.sp -= 2

func pop[T: uint16](self: var Sm83State, mem: var Mcu): T =
  self.sp += 2
  result = mem[self.sp - 2].uint16
  result = result or (mem[self.sp - 1].uint16 shl 8)


func test(cond: JumpCondition, cpu: var Sm83State): bool =
  case cond
  of jcNZ: fZero notin cpu.flags
  of jcZ:  fZero in cpu.flags
  of jcNC: fCarry notin cpu.flags
  of jcC:  fCarry in cpu.flags


template nn(mem: var Mcu, pc: var uint16): uint16 =
  ## Order: LSB, MSB
  let
    lsb = mem.readNext(pc).uint16
    msb = mem.readNext(pc).uint16
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
  print: &"Invalid opcode ({opcode:#04x})"


#[ Jumps/calls ]#
op opJPu16, 4:
  decode:
    let
      nn = mem.nn(pc)
  execute: cpu.pc = nn
  print: &"JP {nn:#x}"

op opJPHL, 1:
  execute: cpu.pc = cpu[rHL]
  print: "JP HL"

op opJPccu16, 3:
  decode:
    let
      nn = mem.nn(pc)
  execute:
    if opcode.cc.test(cpu):
      cpu.pc = nn
      result = 4
  print: &"JP {opcode.cc},{nn:#x}"

op opJRs8, 3:
  decode:
    let
      e = cast[int8](mem.readNext(pc))
  execute: cpu.pc = (cpu.pc.int + e.int).uint16
  print: &"JR {e:#x}"

op opJRccs8, 2:
  decode:
    let
      e = cast[int8](mem.readNext(pc))
  execute:
    if opcode.cc.test(cpu):
      cpu.pc = (cpu.pc.int + e.int).uint16
      result = 3
  print: &"JR {opcode.cc},{e:#x}"

func opCall(cpu: var Sm83State, mem: var Mcu, nn: uint16) =
  cpu.push(mem, cpu.pc)
  cpu.pc = nn

op opCALLu16, 6:
  decode:
    let
      nn = mem.nn(pc)
  execute: opCall(cpu, mem, nn)
  print: &"CALL {nn:#x}"

op opCALLccu16, 3:
  decode:
    let
      nn = mem.nn(pc)
  execute:
    if opcode.cc.test(cpu):
      opCall(cpu, mem, nn)
      result = 6
  print: &"CALL {opcode.cc},{nn:#x}"

op opRET, 4:
  execute: cpu.pc = cpu.pop[:uint16](mem)
  print: &"RET"

op opRETcc, 2:
  execute:
    if opcode.cc.test(cpu):
      cpu.pc = cpu.pop[:uint16](mem)
      result = 5
  print: &"RET {opcode.cc}"

op opRETI, 4:
  execute:
    cpu.pc = cpu.pop[:uint16](mem)
    cpu.ime = 1
  print: "RETI"

op opRST, 4:
  decode:
    const
      Address = [0x00'u16, 0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38]
    let
      rst = Address[(opcode and 0b00111000) shr 3]
  execute:
    cpu.push(mem, cpu.pc)
    cpu.pc = rst
  print: "RST {rst:#x}"


#[ 8bit load/store/move instructions ]#
op opLDr8r8, 1:
  decode:
    let
      xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
      yyy = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[xxx] = cpu[yyy]
  print: &"LD {xxx},{yyy}"

op opLDr8d8, 2:
  decode:
    let
      xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
      b = mem.readNext(pc)
  execute: cpu[xxx] = b
  print: &"LD {xxx},{b:#x}"

op opLDr8HL, 2:
  decode:
    let
      xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
  execute: cpu[xxx] = mem[cpu[rHL]]
  print: &"LD {xxx},(HL)"

op opLDpHLr8, 2:
  decode:
    let
      xxx = ((opcode and 0b00000111) + 2).Register8
  execute: mem[cpu[rHL]] = cpu[xxx]
  print: &"LD (HL),{xxx}"

op opLDpHLA, 2:
  execute: mem[cpu[rHL]] = cpu[rA]
  print: "LD (HL),A"

op opLDHLd8, 3:
  decode:
    let
      b = mem.readNext(pc)
  execute: mem[cpu[rHL]] = b
  print: &"LD (HL),{b:#x}"

op opLDAr8, 1:
  decode:
    let
      yyy = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[rA] = cpu[yyy]
  print: &"LD A,{yyy}"

op opLDAA, 1:
  execute: cpu[rA] = cpu[rA]
  #result.dissasm = "LD A,A"

op opLDr8A, 1:
  decode:
    let
      xxx = (((opcode and 0b00111000) shr 3) + 2).Register8
  execute: cpu[xxx] = cpu[rA]
  print: &"LD {xxx},A"

op opLDAHL, 2:
  execute: cpu[rA] = mem[cpu[rHL]]
  print: "LD A,(HL)"

op opLDAu8, 2:
  decode:
    let
      b = mem.readNext(pc)
  execute: cpu[rA] = b
  print: &"LD A,{b:#x}"

op opLDABC, 2:
  execute: cpu[rA] = mem[cpu[rBC]]
  print: "LD A,(BC)"

op opLDADE, 2:
  execute: cpu[rA] = mem[cpu[rDE]]
  print: "LD A,(DE)"

op opLDBCA, 2:
  execute: mem[cpu[rBC]] = cpu[rA]
  print: "LD (BC),A"

op opLDDEA, 2:
  execute: mem[cpu[rDE]] = cpu[rA]
  print: "LD (DE),A"

op opLDAHLp, 2:
  execute:
    cpu[rA] = mem[cpu[rHL]]
    cpu[rHL] = cpu[rHL] + 1
  print: "LD A,(HL+)"

op opLDAHLm, 2:
  execute:
    cpu[rA] = mem[cpu[rHL]]
    cpu[rHL] = cpu[rHL] - 1
  print: "LD A,(HL-)"

op opLDHLpA, 2:
  execute:
    mem[cpu[rHL]] = cpu[rA]
    cpu[rHL] = cpu[rHL] + 1
  print: "LD (HL+),A"

op opLDHLmA, 2:
  execute:
    mem[cpu[rHL]] = cpu[rA]
    cpu[rHL] = cpu[rHL] - 1
  print: "LD (HL-),A"

op opLDpCA, 2:
  ## Put A into memory at address 0xff00 + C
  execute: mem[0xff00'u16 + cpu[rC].uint16] = cpu[rA]
  print: "LD (C),A"

op opLDApC, 2:
  ## Put memory value at address 0xff00 + C into A
  execute: cpu[rA] = mem[0xff00'u16 + cpu[rC].uint16]
  print: "LD A,(C)"

op opLDHAu8, 3:
  ## Put memory value at address 0xff00 + u8 into A
  decode:
    let
      u8 = mem.readNext(pc)
  execute: cpu[rA] = mem[0xff00'u16 + u8.uint16]
  print: &"LDH A,{u8:#x}"

op opLDHu8A, 3:
  ## Put A into memory at address 0xff00 + u8
  decode:
    let
      u8 = mem.readNext(pc)
  execute: mem[0xff00'u16 + u8.uint16] = cpu[rA]
  print: &"LDH {u8:#x},A"

op opLDAu16, 4:
  decode:
    let
      u16 = mem.nn(pc)
  execute: cpu[rA] = mem[u16]
  print: &"LD A,({u16:#x})"

op opLDu16A, 4:
  decode:
    let
      u16 = mem.nn(pc)
  execute: mem[u16] = cpu[rA]
  print: &"LD ({u16:#x}),A"


#[ 16bit load/store/move instructions ]#
op opLDr16u16, 3:
  decode:
    let
      xx = (opcode and 0b00110000) shr 4
    assert xx in {0, 1, 2, 3}, $xx
    let
      nn = mem.nn(pc)
  execute:
    if xx == 3:
      cpu.sp = nn
    else:
      let
        r16 = (xx + 1).Register16
      cpu[r16] = nn
  print:
    let
      r = if xx == 3: "SP" else: $(xx + 1).Register16
    &"LD {r},{nn:#04x}"

op opLDSPHL, 2:
  execute: cpu.sp = cpu[rHL]
  print: "LD SP,HL"

op opLDHLSPps8, 3:
  decode:
    let
      s8 = mem.readNext(pc)
  execute:
    let
      d8 = cast[int8](s8)
    cpu.flags ?= (hasHalfCarryAdd(7, cpu.sp, s8), { fCarry })
    cpu.flags ?= (hasHalfCarryAdd(3, cpu.sp, s8), { fHalfCarry })
    cpu[rHL] = (cpu.sp.int + d8.int).uint16
    cpu.flags -= { fZero, fAddSub }
  print: &"LD HL,SP+{s8:#x}"

op opLDu16SP, 5:
  decode:
    let
      nn = mem.nn(pc)
  execute: mem[nn] = cpu.sp
  print: &"LD {nn:#x},SP"

op opPOPr16, 3:
  decode:
    let
      xx = (opcode and 0b00110000) shr 4 + 1
    assert xx in {1, 2, 3, 4}
    let
      r16 = (if xx == 4: 0'u8 else: xx).Register16
  execute:
    cpu[r16] = cpu.pop[:uint16](mem)
    if r16 == rAF:
      # zero out the lower nibble of register f since it cannot be modified
      cpu[rF] = cpu[rF] and 0b11110000
  print: &"POP {r16}"

op opPUSHr16, 4:
  decode:
    let
      xx = ((opcode and 0b00110000) shr 4)
    assert xx in {0, 1, 2, 3}
    let
      r16 = if xx == 3: rAF else: (xx + 1).Register16
  execute: cpu.push(mem, cpu[r16])
  print: &"PUSH {r16}"


#[ 8bit arithmetic/logical instructions ]#
func opXor(cpu: var Sm83State, value: uint8) =
  cpu[rA] = cpu[rA] xor value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry, fCarry }

op opXORr8, 1:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: opXor(cpu, cpu[r8])
  print: &"XOR {r8}"

op opXORpHL, 2:
  execute: opXor(cpu, mem[cpu[rHL]])
  print: "XOR (HL)"

op opXORA, 1:
  execute: opXor(cpu, cpu[rA])
  print: "XOR A"

op opXORd8, 2:
  decode:
    let
      d8 = mem.readNext(pc)
  execute: opXor(cpu, d8)
  print: &"XOR {d8}"

func opInc(cpu: var Sm83State, mem: var Mcu, value: uint8): uint8 = 
  result = value + 1
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub }
  cpu.flags ?= (hasHalfCarryAdd(value, 1), { fHalfCarry })

op opINCr8, 1:
  decode:
    let
      r8 = (((opcode and 0b00111000) shr 3) + 2).Register8
  execute: cpu[r8] = cpu.opInc(mem, cpu[r8])
  print: &"INC {r8}"

op opINCpHL, 3:
  execute: mem[cpu[rHL]] = cpu.opInc(mem, mem[cpu[rHL]])
  print: &"INC HL"

op opINCA, 1:
  execute: cpu[rA] = cpu.opInc(mem, cpu[rA])
  print: &"INC A"

func opDec(cpu: var Sm83State, mem: var Mcu, value: uint8): uint8 = 
  result = value - 1
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags += { fAddSub }
  cpu.flags ?= (hasHalfCarrySub(value, 1), { fHalfCarry })

op opDECr8, 1:
  decode:
    let
      r8 = (((opcode and 0b00111000) shr 3) + 2).Register8
  execute: cpu[r8] = cpu.opDec(mem, cpu[r8])
  print: &"DEC {r8}"

op opDECpHL, 3:
  execute: mem[cpu[rHL]] = cpu.opDec(mem, mem[cpu[rHL]])
  print: &"INC HL"

op opDECA, 1:
  execute: cpu[rA] = cpu.opDec(mem, cpu[rA])
  print: &"DEC A"

func opCp(cpu: var Sm83State, value: uint8) =
  cpu.flags ?= (cpu[rA] < value, { fCarry })
  cpu.flags ?= (hasHalfCarrySub(cpu[rA], value), { fHalfCarry })
  let
    res = cpu[rA] - value
  cpu.flags ?= (res == 0, { fZero })
  cpu.flags += { fAddSub }

op opCPr8, 1:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: opCp(cpu, cpu[r8])
  print: &"CP {r8}"

op opCPpHL, 2:
  execute: opCp(cpu, mem[cpu[rHL]])
  print: &"CP (HL)"

op opCPA, 1:
  execute: opCp(cpu, cpu[rA])
  print: &"CP A"

op opCPu8, 2:
  decode:
    let
      u8 = mem.readNext(pc)
  execute: opCp(cpu, u8)
  print: &"CP {u8:#x}"

func opSub(cpu: var Sm83State, value: uint8) =
  cpu.flags ?= (cpu[rA] < value, { fCarry })
  cpu.flags ?= (hasHalfCarrySub(cpu[rA], value), { fHalfCarry })
  cpu[rA] = cpu[rA] - value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags += { fAddSub }

op opSUBr8, 1:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: opSub(cpu, cpu[r8])
  print: &"SUB {r8}"

op opSUBHL, 2:
  execute: opSub(cpu, mem[cpu[rHL]])
  print: "SUB (HL)"

op opSUBA, 1:
  execute: opSub(cpu, cpu[rA])
  print: "SUB A"

op opSUBd8, 2:
  decode:
    let
      d8 = mem.readNext(pc)
  execute: opSub(cpu, d8)
  print: &"SUB {d8}"

func opAdd(cpu: var Sm83State, value: uint8) =
  cpu.flags ?= (cpu[rA].int + value.int > uint8.high.int, { fCarry })
  cpu.flags ?= (hasHalfCarryAdd(cpu[rA], value), { fHalfCarry })
  cpu[rA] = cpu[rA] + value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub }

op opADDAr8, 1:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: opAdd(cpu, cpu[r8])
  print: &"ADD A,{r8}"

op opADDAHL, 2:
  execute: opAdd(cpu, mem[cpu[rHL]])
  print: &"ADD A,(HL)"

op opADDAA, 1:
  execute: opAdd(cpu, cpu[rA])
  print: &"ADD A,A"

op opADDAd8, 2:
  decode:
    let
      d8 = mem.readNext(pc)
  execute: opAdd(cpu, d8)
  print: &"ADD A,{d8}"

func opOr(cpu: var Sm83State, mem: var Mcu, value: uint8) =
  cpu[rA] = cpu[rA] or value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry, fCarry }

op opORr8, 1:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: opOr(cpu, mem, cpu[r8])
  print: &"OR {r8}"

op opORpHL, 2:
  execute: opOr(cpu, mem, mem[cpu[rHL]])
  print: &"OR (HL)"

op opORA, 1:
  execute: opOr(cpu, mem, cpu[rA])
  print: &"OR A"

op opORd8, 2:
  decode:
    let
      d8 = mem.readNext(pc)
  execute: opOr(cpu, mem, d8)
  print: &"OR {d8}"

op opCPL, 1:
  execute:
    cpu[rA] = not cpu[rA]
    cpu.flags += { fAddSub, fHalfCarry }
  print: "CPL"

func opAnd(cpu: var Sm83State, mem: var Mcu, value: uint8) =
  cpu[rA] = cpu[rA] and value
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags += { fHalfCarry }
  cpu.flags -= { fAddSub, fCarry }

op opANDr8, 1:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: opAnd(cpu, mem, cpu[r8])
  print: &"AND {r8}"

op opANDpHL, 2:
  execute: opAnd(cpu, mem, mem[cpu[rHL]])
  print: &"AND (HL)"

op opANDA, 1:
  execute: opAnd(cpu, mem, cpu[rA])
  print: &"AND A"

op opANDd8, 2:
  decode:
    let
      d8 = mem.readNext(pc)
  execute: opAnd(cpu, mem, d8)
  print: &"AND {d8}"

op opSCF, 1:
  execute:
    cpu.flags -= { fAddSub, fHalfCarry }
    cpu.flags += { fCarry }
  print: &"SCF"

op opCCF, 1:
  execute:
    cpu.flags -= { fAddSub, fHalfCarry }
    cpu.flags ?= (fCarry notin cpu.flags, { fCarry })
  print: &"CCF"

func opAdc(cpu: var Sm83State, value: uint8) =
  let
    carry = if fCarry in cpu.flags: 1'u8 else: 0
  cpu.flags ?= (cpu[rA].int + value.int + carry.int > 255, { fCarry })
  cpu.flags ?= (hasHalfCarryAdd(cpu[rA], value) or hasHalfCarryAdd(cpu[rA] + value, carry), { fHalfCarry })
  cpu[rA] = cpu[rA] + value + carry
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags -= { fAddSub }

op opADCr8, 1:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: opAdc(cpu, cpu[r8])
  print: &"ADC A,{r8}"

op opADCpHL, 2:
  execute: opAdc(cpu, mem[cpu[rHL]])
  print: "ADC A,(HL)"

op opADCA, 1:
  execute: opAdc(cpu, cpu[rA])
  print: "ADC A,A"

op opADCd8, 2:
  decode:
    let
      n = mem.readNext(pc)
  execute: opAdc(cpu, n)
  print: &"ADC A,{n}"

func opSbc(cpu: var Sm83State, value: uint8) =
  let
    carry = if fCarry in cpu.flags: 1'u8 else: 0
  cpu.flags ?= (value.int + carry.int > cpu[rA].int, { fCarry })
  cpu.flags ?= (hasHalfCarrySub(cpu[rA], value) or hasHalfCarrySub(cpu[rA] - value, carry), { fHalfCarry })
  cpu[rA] = cpu[rA] - value - carry
  cpu.flags ?= (cpu[rA] == 0, { fZero })
  cpu.flags += { fAddSub }

op opSBCr8, 1:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: opSbc(cpu, cpu[r8])
  print: &"SDC A,{r8}"

op opSBCpHL, 2:
  execute: opSbc(cpu, mem[cpu[rHL]])
  print: "SDC A,(HL)"

op opSBCA, 1:
  execute: opSbc(cpu, cpu[rA])
  print: "SDC A,A"

op opSBCd8, 2:
  decode:
    let
      n = mem.readNext(pc)
  execute: opSbc(cpu, n)
  print: &"SDC A,{n}"

op opDAA, 1:
  # from: http://forums.nesdev.com/viewtopic.php?f=20&t=15944#p196282
  # note: assumes a is a uint8_t and wraps from 0xff to 0
  execute:
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
  print: "DAA"


#[ 16bit arithmetic/logical instructions ]#
op opINCr16, 2:
  decode:
    let
      r16 = (((opcode and 0b00110000) shr 4) + 1).Register16
  execute: cpu[r16] = cpu[r16] + 1
  print: &"INC {r16}"

op opINCSP, 2:
  execute: cpu.sp = cpu.sp + 1
  print: &"INC SP"

op opDECr16, 2:
  decode:
    let
      r16 = (((opcode and 0b00110000) shr 4) + 1).Register16
  execute: cpu[r16] = cpu[r16] - 1
  print: &"DEC {r16}"

op opDECSP, 2:
  execute: cpu.sp = cpu.sp - 1
  print: &"DEC SP"

func opAddHl(cpu: var Sm83State, value: uint16) =
  cpu.flags ?= (cpu[rHL] > uint16.high - value, { fCarry })
  cpu.flags ?= (hasHalfCarryAdd(11, cpu[rHL], value), { fHalfCarry })
  cpu[rHL] = cpu[rHL] + value
  cpu.flags -= { fAddSub }

op opADDHLr16, 2:
  decode:
    let
      r16 = (((opcode and 0b00110000) shr 4) + 1).Register16
  execute: opAddHl(cpu, cpu[r16])
  print: &"ADD HL,{r16}"

op opADDHLSP, 2:
  execute: opAddHl(cpu, cpu.sp)
  print: "ADD HL,SP"

op opADDSPs8, 4:
  decode:
    let
      s8 = mem.readNext(pc)
  execute:
    let
      d8 = cast[int8](s8)
    cpu.flags ?= (hasHalfCarryAdd(7, cpu.sp, s8), { fCarry })
    cpu.flags ?= (hasHalfCarryAdd(3, cpu.sp, s8), { fHalfCarry })
    cpu.sp = (cpu.sp.int + d8.int).uint16
    cpu.flags -= { fZero, fAddSub }
  print: &"ADD SP,{s8}"


#[ 8bit rotations/shifts and bit instructions ]#
func opRlc(cpu: var Sm83State, value: uint8): uint8 =
  let
    carry = (value and 0b10000000) shr 7
  result = (value shl 1) or carry
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })

op opRLCr8, 2:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opRlc(cpu, cpu[r8])
  print: &"RLC {r8}"

op opRLCpHL, 4:
  execute: mem[cpu[rHL]] = opRlc(cpu, mem[cpu[rHL]])
  print: &"RLC (HL)"

op opRLCA, 1:
  execute:
    cpu[rA] = opRlc(cpu, cpu[rA])
    cpu.flags -= { fZero }
  print: &"RLC A"

op opCBRLCA, 2:
  execute: cpu[rA] = opRlc(cpu, cpu[rA])
  print: &"RLC A"

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
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opRl(cpu, cpu[r8])
  print: &"RL {r8}"

op opRLpHL, 4:
  execute: mem[cpu[rHL]] = opRl(cpu, mem[cpu[rHL]])
  print: &"RL (HL)"

op opRLA, 1:
  execute:
    cpu[rA] = opRl(cpu, cpu[rA])
    cpu.flags -= { fZero }
  print: &"RL A"

op opCBRLA, 2:
  execute: cpu[rA] = opRl(cpu, cpu[rA])
  print: &"RL A"

func opSla(cpu: var Sm83State, value: uint8): uint8 =
  let
    carry = (value and 0b10000000) shr 7
  result = value shl 1
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })

op opSLAr8, 2:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opSla(cpu, cpu[r8])
  print: &"SLA {r8}"

op opSLApHL, 4:
  execute: mem[cpu[rHL]] = opSla(cpu, mem[cpu[rHL]])
  print: &"SLA (HL)"

op opSLAA, 2:
  execute: cpu[rA] = opSla(cpu, cpu[rA])
  print: &"SLA A"

func opBit(cpu: var Sm83State, bit: range[0..7], value: uint8) =
  cpu.flags ?= (not testBit(value, bit.int), { fZero })
  cpu.flags -= { fAddSub }
  cpu.flags += { fHalfCarry }

op opBITr8, 2:
  decode:
    let
      bit = opcode.bit
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: opBit(cpu, bit, cpu[r8])
  print: &"BIT {bit},{r8}"

# TODO: Every source I could find mentions 4 cycles, but blargg test roms look for 3
op opBITpHL, 3:
  decode:
    let
      bit = opcode.bit
  execute: opBit(cpu, bit, mem[cpu[rHL]])
  print: &"BIT {bit},(HL)"

op opBITA, 2:
  decode:
    let
      bit = opcode.bit
  execute: opBit(cpu, bit, cpu[rA])
  print: &"BIT {bit},A"

func opSet(bit: range[0..7], value: uint8): uint8 =
  result = value
  setBit[uint8](result, bit)

op opSETbr8, 2:
  decode:
    let
      bit = opcode.bit
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opSet(bit, cpu[r8])
  print: &"SET {bit},{r8}"

op opSETbpHL, 4:
  decode:
    let
      bit = opcode.bit
  execute: mem[cpu[rHL]] = opSet(bit, mem[cpu[rHL]])
  print: &"SET {bit},(HL)"

op opSETbA, 2:
  decode:
    let
      bit = opcode.bit
  execute: cpu[rA] = opSet(bit, cpu[rA])
  print: &"SET {bit},A"

func opRes(bit: range[0..7], value: uint8): uint8 =
  result = value
  clearBit[uint8](result, bit)

op opRESbr8, 2:
  decode:
    let
      bit = opcode.bit
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opRes(bit, cpu[r8])
  print: &"RES {bit},{r8}"

op opRESbpHL, 4:
  decode:
    let
      bit = opcode.bit
  execute: mem[cpu[rHL]] = opRes(bit, mem[cpu[rHL]])
  print: &"RES {bit},(HL)"

op opRESbA, 2:
  decode:
    let
      bit = opcode.bit
  execute: cpu[rA] = opRes(bit, cpu[rA])
  print: &"RES {bit},A"

func opSwap(cpu: var Sm83State, value: uint8): uint8 =
  result = ((value and 0x0f) shl 4) or ((value and 0xf0) shr 4)
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry, fCarry }

op opSWAPr8, 2:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opSwap(cpu, cpu[r8])
  print: &"SWAP {r8}"

op opSWAPpHL, 4:
  execute: mem[cpu[rHL]] = opSwap(cpu, mem[cpu[rHL]])
  print: &"SWAP (HL)"

op opSWAPA, 2:
  execute: cpu[rA] = opSwap(cpu, cpu[rA])
  print: &"SWAP A"

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
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opRrc(cpu, cpu[r8])
  print: &"RRC {r8}"

op opRRCpHL, 4:
  execute: mem[cpu[rHL]] = opRrc(cpu, mem[cpu[rHL]])
  print: &"RRC (HL)"

op opRRCA, 1:
  execute:
    cpu[rA] = opRrc(cpu, cpu[rA])
    cpu.flags -= { fZero }
  print: &"RRC A"

op opCBRRCA, 2:
  execute: cpu[rA] = opRrc(cpu, cpu[rA])
  print: &"RRCA"

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
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opRr(cpu, cpu[r8])
  print: &"RR {r8}"

op opRRpHL, 4:
  execute: mem[cpu[rHL]] = opRr(cpu, mem[cpu[rHL]])
  print: &"RR (HL)"

op opRRA, 1:
  execute:
    cpu[rA] = opRr(cpu, cpu[rA])
    cpu.flags -= { fZero }
  print: &"RR A"

op opCBRRA, 2:
  execute: cpu[rA] = opRr(cpu, cpu[rA])
  print: &"RRA"

func opSra(cpu: var Sm83State, value: uint8): uint8 =
  let
    msb = value and 0b10000000
    carry = value and 0b00000001
  result = (value shr 1) or msb
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })

op opSRAr8, 2:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opSra(cpu, cpu[r8])
  print: &"SRA {r8}"

op opSRApHL, 4:
  execute: mem[cpu[rHL]] = opSra(cpu, mem[cpu[rHL]])
  print: &"SRA (HL)"

op opSRAA, 2:
  execute: cpu[rA] = opSra(cpu, cpu[rA])
  print: &"SRA A"

func opSrl(cpu: var Sm83State, value: uint8): uint8 =
  let
    carry = value and 0b00000001
  result = value shr 1
  cpu.flags ?= (result == 0, { fZero })
  cpu.flags -= { fAddSub, fHalfCarry }
  cpu.flags ?= (carry == 1, { fCarry })

op opSRLr8, 2:
  decode:
    let
      r8 = ((opcode and 0b00000111) + 2).Register8
  execute: cpu[r8] = opSrl(cpu, cpu[r8])
  print: &"SRL {r8}"

op opSRLpHL, 4:
  execute: mem[cpu[rHL]] = opSrl(cpu, mem[cpu[rHL]])
  print: &"SRL (HL)"

op opSRLA, 2:
  execute: cpu[rA] = opSrl(cpu, cpu[rA])
  print: &"SRL A"


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
  print: "NOP"

op opSTOP, 1:
  execute: cpu.status += { sfStopped }
  print: "STOP"

op opHALT, 1:
  execute: cpu.status += { sfHalted }
  print: "HALT"

op opPreCB, 1:
  decode:
    let
      opcode = mem.readNext(pc)
      instruction = PrefixCbTable[opcode.int]
  execute: result = instruction.exec(opcode, mem, pc, cpu)
  print: instruction.diss(opcode, mem, pc)

op opDI, 1:
  ## Disable interrupt handling (ime = 0) after the next instruction
  execute: cpu.status += { sfInterruptWait, sfInterruptDisable }
  print: "DI"

op opEI, 1:
  ## Enable interrupt handling (ime = 1) after the next instruction
  execute: cpu.status += { sfInterruptWait, sfInterruptEnable }
  print: "EI"

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


func dissasemble*(mem: var Mcu, pc: var uint16): string =
  let
    opcode = mem.readNext(pc)
    instruction = OpcodeTable[opcode.int]
  instruction.diss(opcode, mem, pc)

func step*(self: var Sm83, mem: var Mcu): int {.discardable.} =
  if self.state.`if` != {}:
    self.state.status -= { sfHalted, sfStopped }
    if self.state.ime == 1:
      for interrupt in Interrupt:
        if interrupt in self.state.ie and interrupt in self.state.`if`:
          self.state.ime = 0
          self.state.`if` -= { interrupt }
          opCall(self.state, mem, InterruptHandler[interrupt])
          return 5

  if sfHalted in self.state.status or  sfStopped in self.state.status:
    return 1

  let
    opcode = mem.readNext(self.state.pc)
    instruction = OpcodeTable[opcode.int]
  let
    cycles = instruction.exec(opcode, mem, self.state.pc, self.state)

  if sfInterruptWait notin self.state.status:
    if sfInterruptEnable in self.state.status:
      self.state.ime = 1
      self.state.status -= { sfInterruptEnable }
    
    if sfInterruptDisable in self.state.status:
      self.state.ime = 0
      self.state.status -= { sfInterruptDisable }
  else:
    self.state.status -= { sfInterruptWait }

  cycles
