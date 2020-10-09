##[

  ARM7TDMI

  Sources

  * `<https://mgba.io/2015/06/27/cycle-counting-prefetch/>`_
  * `<https://stackoverflow.com/a/24092329>`_

]##
import
  std/strformat,
  gb/common/util, mem, cpu_decode



type
  BankedRegister[D: static[int], T] = object
    values: array[D, T]
    current: range[0..(D-1)]

func switchTo[D: static[int], T](bank: var BankedRegister[D, T], i: range[0..(D-1)]) =
  bank.current = i

func `[]`[D: static[int], T](bank: var BankedRegister[D, T]): var T =
  bank.values[bank.current]

func `[]`[D: static[int], T](bank: BankedRegister[D, T]): T =
  bank.values[bank.current]

func `[]=`[D: static[int], T](bank: var BankedRegister[D, T], value: T) =
  bank.values[bank.current] = value



type
  InstructionSet = enum
    isArm
    isThumb

  Mode* = enum
    mUser       = 0b10000  ## The program execution state
    mFiq        = 0b10001  ## Designed to support a data transfer or channel process
    mIrq        = 0b10010  ## Used for generalpurpose interrupt handling
    mSupervisor = 0b10011  ## Protected mode for the operating system
    mAbort      = 0b10111  ## Entered after a data or instruction prefetch abort
    mUndefined  = 0b11011  ## Entered when an undefined instruction is executed
    mSystem     = 0b11111  ## A privileged user mode for the operating system

  ProgramStatus = enum
    psM0 = 00
    psM1 = 01
    psM2 = 02
    psM3 = 03
    psM4 = 04
    psT  = 05
    psF  = 06
    psI  = 07
    psV  = 28
    psC  = 29
    psZ  = 30
    psN  = 31
  
  ProgramStatusRegister* = set[ProgramStatus]
  
  Arm7tdmiState* = tuple
    instructions: InstructionSet
    r0: uint32
    r1: uint32
    r2: uint32
    r3: uint32
    r4: uint32
    r5: uint32
    r6: uint32
    r7: uint32
    r8: BankedRegister[2, uint32]
    r9: BankedRegister[2, uint32]
    r10: BankedRegister[2, uint32]
    r11: BankedRegister[2, uint32]
    r12: BankedRegister[2, uint32]
    r13: BankedRegister[6, uint32]
    r14: BankedRegister[6, uint32]
    r15: uint32
    cpsr: ProgramStatusRegister
    spsr: BankedRegister[6, ProgramStatusRegister]

const
  ArmInstructionSize = sizeof(ArmInstruction).uint32


converter statusRegisterToUint32(status: ProgramStatusRegister): uint32 =
  cast[uint32](status)

converter uint32ToStatusRegister(status: uint32): ProgramStatusRegister =
  cast[ProgramStatusRegister](status)


proc mode(status: ProgramStatusRegister): Mode =
  (statusRegisterToUint32(status) and 0x1f).Mode

proc `mode=`(status: var ProgramStatusRegister, mode: Mode) =
  status += uint32ToStatusRegister(mode.uint32)

func bankIndices(mode: Mode): tuple[a, s: int] =
  case mode
  of mUser: (a: 0, s: 0)
  of mFiq: (a: 1, s: 1)
  of mIrq: (a: 0, s: 4)
  of mSupervisor: (a: 0, s: 2)
  of mAbort: (a: 0, s: 3)
  of mUndefined: (a: 0, s: 5)
  of mSystem: (a: 0, s: 0)


proc `mode=`*(state: var Arm7tdmiState, mode: Mode) =
  state.cpsr.mode = mode

  let
    (armBankIndex, isOther) = mode.bankIndices()
  state.r8.switchTo(armBankIndex)
  state.r9.switchTo(armBankIndex)
  state.r10.switchTo(armBankIndex)
  state.r11.switchTo(armBankIndex)
  state.r12.switchTo(armBankIndex)
  state.r13.switchTo(isOther)
  state.r14.switchTo(isOther)
  if isOther != 0:
    state.spsr.switchTo(isOther)
    state.spsr[] = state.cpsr

proc reg*(state: var Arm7tdmiState, i: range[0..15]): var uint32 =
  # TODO: this is really ugly - a better solution?
  case i
  of 0: return state.r0
  of 1: return state.r1
  of 2: return state.r2
  of 3: return state.r3
  of 4: return state.r4
  of 5: return state.r5
  of 6: return state.r6
  of 7: return state.r7
  of 8: return state.r8[]
  of 9: return state.r9[]
  of 10: return state.r10[]
  of 11: return state.r11[]
  of 12: return state.r12[]
  of 13: return state.r13[]
  of 14: return state.r14[]
  of 15: return state.r15

proc reg*(state: Arm7tdmiState, i: range[0..15]): uint32 =
  # TODO: this is really ugly - a better solution?
  case i
  of 0: return state.r0
  of 1: return state.r1
  of 2: return state.r2
  of 3: return state.r3
  of 4: return state.r4
  of 5: return state.r5
  of 6: return state.r6
  of 7: return state.r7
  of 8: return state.r8[]
  of 9: return state.r9[]
  of 10: return state.r10[]
  of 11: return state.r11[]
  of 12: return state.r12[]
  of 13: return state.r13[]
  of 14: return state.r14[]
  of 15: return state.r15

template sp(state: Arm7tdmiState): var uint32 = state.reg(13)
template `sp=`(state: var Arm7tdmiState, value: uint32) = state.reg(13) = value

template lr(state: Arm7tdmiState): var uint32 = state.reg(14)
template `lr=`(state: var Arm7tdmiState, value: uint32) = state.reg(14) = value

template pc*(state: Arm7tdmiState): uint32 = state.reg(15)
template `pc=`*(state: var Arm7tdmiState, value: uint32) =
  # TODO: actually prefetch 2 opcodes instead of this
  # TODO: Thumb support
  # TODO: this should happen even if r15 is directly assigned
  state.reg(15) = value + 2*ArmInstructionSize



proc `$`*(self: Arm7tdmiState): string =
  result = ""
  for r in 0..15:
    result &= &"\tr{r:<3}: {self.reg(r).uint64:#010x}\n"
  result &= &"\tcpsr: {cast[uint32](self.cpsr).uint64:#010x}\t{self.cpsr}\n"
  result &= &"\tspsr: {cast[uint32](self.spsr[]).uint64:#010x}"



#[

  ARM Conditions

]#
proc check(condition: Condition, state: Arm7tdmiState): bool =
  let
    status = state.cpsr
  case condition
  of cEQ: psZ in status
  of cNE: psZ notin status
  of cCS: psC in status
  of cCC: psC notin status
  of cMI: psN in status
  of cPL: psN notin status
  of cVS: psV in status
  of cVC: psV notin status
  of cHI: psC in status and psZ notin status
  of cLS: psC notin status and psZ in status
  of cGE: (psN in status) == (psV in status)
  of cLT: (psN in status) != (psV in status)
  of cGT: psZ notin status and ((psN in status) == (psV in status))
  of cLE: psZ in status or ((psN in status) != (psV in status))
  of cAL: true

proc checkCondition(instr: uint32, state: Arm7tdmiState): bool =
  ## Check bits 31..28 of the ARM instruction. Throws an exception on _1111_.
  ## 
  ## See: Page 30 [36]
  (instr shr 28).Condition.check(state)

proc checkCondition(op: ArmOp, state: Arm7tdmiState): bool =
  ## Check bits 31..28 of the ARM instruction. Throws an exception on _1111_.
  ## 
  ## See: Page 30 [36]
  op.condition.check(state)



func opcode*(instr: ArmInstruction): uint32 =
  instr.extract(21, 24)

func rn*(instr: ArmInstruction): int =
  instr.extract(16, 19).int

func rd*(instr: ArmInstruction): int =
  instr.extract(12, 15).int

func s*(instr: ArmInstruction): bool =
  instr.testBit(20)

func i*(instr: ArmInstruction): bool =
  instr.testBit(25)

func rotate*(instr: ArmInstruction): uint32 =
  instr.extract(8, 11)

func imm*(instr: ArmInstruction): uint32 =
  instr.extract(0, 7)

func operandImmediate*(instr: ArmInstruction): uint32 =
  instr.imm.rotateRight(instr.rotate * 2)

type
  ShiftType = enum
    stLSL   ## Logical Shift Left
    stLSR   ## Logical Shift Right
    stASR   ## Airthmetic Shift Right
    stROR   ## ROtate Right

func rm*(instr: ArmInstruction): int =
  instr.extract(0, 3).int





#[ ######################################################################################

    Branch Instructions

]# ######################################################################################
proc opArmBxDecode(cpu: var Arm7tdmiState, opcode: ArmInstruction): tuple[rn: int] =
  result.rn = (opcode and 0b1111).int
  assert result.rn != 15, "Using R15 as BX operand result in undefined behaviour"

proc opArmBxExecute(cpu: var Arm7tdmiState, data: tuple[rn: int]) =
  let
    value = cpu.reg(data.rn)
    asThumb = value.testBit(0)
  if asThumb:
    cpu.instructions = isThumb
  else:
    cpu.instructions = isArm
  cpu.pc = value
  cpu.pc.clearBit(0)
  # TODO: 2S + 1N cycles

proc opArmBx(cpu: var Arm7tdmiState, opcode: ArmInstruction) =
  let
    data = cpu.opArmBxDecode(opcode)
  cpu.opArmBxExecute(data)
  # TODO: 2S + 1N cycles


proc opArmB(cpu: var Arm7tdmiState, instr: ArmInstruction) =
  let
    offset = cast[int32](instr.extract(0, 23).uint32.signExtend(24)) * 4
    isLink = instr.testBit(24)
  if isLink:
    cpu.lr = cpu.pc - 2*ArmInstructionSize
  cpu.pc = (cpu.pc.int + offset.int).uint32 - ArmInstructionSize
  # TODO: 2S + 1N cycles



#[ ######################################################################################

    ALU instructions

]# ######################################################################################
func immediateValue(op: OpAluOperand, cpu: Arm7tdmiState, carry: var bool): uint32 =
  result = op.imm.rotateRight(op.rotate * 2)
  carry = result.testBit(31)

func registerValue(op: OpAluOperand, cpu: Arm7tdmiState, carry: var bool): uint32 =
  ##
  ## bit 0   - 0: immediate value, 1: register
  ## bit 1-2 - Shift Type (0=LSL, 1=LSR, 2=ASR, 3=ROR)
  ##
  ## Shift by Immediate
  ##
  ##   7       3 2 1 0
  ##  +-+-+-+-+-+-+-+-+
  ##  | amount  |   |0|
  ##  +-+-+-+-+-+-+-+-+
  ##
  ##   bit 3-7 - Shift amount (1-31, 0=Special)
  ## 
  ## Shift by Register
  ##   7     4 3 2 1 0
  ##  +-+-+-+-+-+-+-+-+
  ##  |  rs   |0|   |1|
  ##  +-+-+-+-+-+-+-+-+
  ## 
  ##   bit 3   - Reserved, must be zero  (otherwise multiply or LDREX or undefined)
  ##   bit 4-7 - Rs - Shift register (R0-R14) - only lower 8bit 0-255 used
  ##
  let
    isShiftRegister = op.shift.testBit(0)
    shiftType = op.shift.extract(1, 2).ShiftType
    shiftAmount =
      if isShiftRegister:
        assert not op.shift.testBit(3), "ALU instructions: if shift amount is specified in a register bit 7 has to be 0"
        let
          rs = op.shift.extract(4, 7)
        assert rs != 15, "ALU instructions: shift amount register (Rs) cannot be R15"
        cpu.reg(rs) and 0x000000ff
      else:
        op.shift.extract(3, 7)
    shiftValue = cpu.reg(op.rm)

  if isShiftRegister and shiftAmount == 0:
    return shiftValue

  result =
    case shiftType
    of stLSL:
      if shiftAmount == 0:
        cpu.reg(op.rm)
      else:
        carry = if shiftAmount > 32: false else: shiftValue.testBit(32 - shiftAmount)
        if shiftAmount > 31:
          0'u32
        else:
          shiftValue shl shiftAmount
    of stLSR:
      let
        amount = if shiftAmount == 0: 32'u32 else: shiftAmount
      carry = if amount > 32: false else: shiftValue.testBit(amount - 1)
      if amount > 31:
        0'u32
      else:
        shiftValue shr amount
    of stASR:
      let
        amount = if shiftAmount == 0: 32'u32 else: shiftAmount
      carry = shiftValue.testBit(amount - 1)
      ashr(shiftValue, amount)
    of stROR:
      if shiftAmount == 0:
        let
          oldCarry = (psC in cpu.cpsr).uint32
        carry = shiftValue.testBit(0)
        (shiftValue shr 1) or (oldCarry shl 31)
      else:
        let
          r = rotateRight(shiftValue, shiftAmount)
        carry = r.testBit(31)
        r
  

func value(op: OpAluOperand, cpu: Arm7tdmiState, shiftCarry: var bool): uint32 =
  if op.isImmediate:
    op.immediateValue(cpu, shiftCarry)
  else:
    op.registerValue(cpu, shiftCarry)

func operands(op: OpAlu, cpu: Arm7tdmiState, shiftCarry: var bool): tuple[op1, op2: uint32] =
  (
    op1: cpu.reg(op.rn),
    op2: op.operand2.value(cpu, shiftCarry)
  )

func operands(op: OpAlu, cpu: Arm7tdmiState): tuple[op1, op2: uint32] =
  var
    carry: bool
  op.operands(cpu, carry)



# TODO: create a macro to call these automatically

proc builtin_add_overflow(a, b: uint32, res: var uint32): bool
  {.importc: "__builtin_add_overflow", nodecl, noSideEffect.}

proc builtin_sub_overflow(a, b: uint32, res: var uint32): bool
  {.importc: "__builtin_sub_overflow", nodecl, noSideEffect.}


func airthmeticFlags(cpu: var Arm7tdmiState, rd: range[0..15], r, op1, op2: uint32) =
  cpu.cpsr ?= (op1.testBit(31) != r.testBit(31), { psV })
  cpu.cpsr ?= (r == 0, { psZ })
  #cpu.cpsr ?= (op1 <= op2, { psC })
  cpu.cpsr ?= (r.testBit(31), { psN })

func logicFlags(cpu: var Arm7tdmiState, rd: range[0..15], r: uint32, carry: bool) =
  cpu.cpsr ?= (r == 0, { psZ })
  cpu.cpsr ?= (carry, { psC })
  cpu.cpsr ?= (r.testBit(31), { psN })


func opAnd(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0b0000
  ## Rd := Operand1 AND Operand2
  var
    shiftCarry = psC in cpu.cpsr
  let
    (op1, op2) = op.operands(cpu, shiftCarry)
    r = op1 and op2
  if op.s:
    cpu.logicFlags(op.rd, op1, shiftCarry)
  cpu.reg(op.rd) = r

func opEor(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0b0001
  ## Rd := Operand1 EOR Operand2
  var
    shiftCarry = psC in cpu.cpsr
  let
    (op1, op2) = op.operands(cpu, shiftCarry)
    r = op1 xor op2
  if op.s:
    cpu.logicFlags(op.rd, op1, shiftCarry)
  cpu.reg(op.rd) = r

func opSub(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0010
  ## Rd := Operand1 - Operand2
  let
    (op1, op2) = op.operands(cpu)
    r = op1 - op2
  if op.s:
    let
      (r, c) =
        block:
        var
          r = op1
          c = false
        c = c or builtin_sub_overflow(r, op2, r)
        (r, c)
    cpu.airthmeticFlags(op.rd, r, op1, op2)
    cpu.cpsr ?= (not c, { psC })
  cpu.reg(op.rd) = r
  
  if op.rd == 15:
    cpu.reg(op.rd) += ArmInstructionSize*2

func opRsb(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0011
  ## Rd := Operand2 - Operand1
  let
    (op1, op2) = op.operands(cpu)
    r = op2 - op1
  if op.s:
    cpu.airthmeticFlags(op.rd, r, op2, op1)
  cpu.reg(op.rd) = r

func opAdd(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0100
  ## Rd := Operand1 + Operand2
  let
    (op1, op2) = op.operands(cpu)
    r = op1 + op2
  if op.s:
    let
      (r, c) =
        block:
        var
          r = op1
          c = false
        c = c or builtin_add_overflow(r, op2, r)
        (r, c)
    cpu.airthmeticFlags(op.rd, r, op1, op2)
    cpu.cpsr ?= (c, { psC })
  cpu.reg(op.rd) = r

func opAdc(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0101
  ## Rd := Operand1 + Operand2 + carry
  let
    (op1, op2) = op.operands(cpu)
    carry = (if psC in cpu.cpsr: 1'u32 else: 0'u32)
    r = op1 + op2 + carry
  if op.s:
    var
      r = op1
      c = false
    c = c or builtin_add_overflow(r, op2, r)
    c = c or builtin_add_overflow(r, carry, r)
    cpu.airthmeticFlags(op.rd, r, op1, op2)
    cpu.cpsr ?= (c, { psC })
  cpu.reg(op.rd) = r

func opSbc(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0110
  ## Rd := Operand1 - Operand2 + carry - 1
  let
    (op1, op2) = op.operands(cpu)
    carry = (if psC in cpu.cpsr: 1'u32 else: 0'u32)
    r = op1 - op2 + carry - 1
  if op.s:
    let
      (r, c) =
        block:
        var
          r = op1
          c = false
        c = c or builtin_sub_overflow(r, op2, r)
        c = c or builtin_add_overflow(r, carry, r)
        c = c or builtin_sub_overflow(r, 1, r)
        (r, c)
    cpu.airthmeticFlags(op.rd, r, op1, op2)
    cpu.cpsr ?= (not c, { psC })
  cpu.reg(op.rd) = r

func opRsc(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0111
  ## Rd := Operand2 - Operand1 + carry - 1
  # TODO: include the carry in the overflow calculation
  let
    (op1, op2) = op.operands(cpu)
    carry = (if psC in cpu.cpsr: 1'u32 else: 0'u32)
    r = op2 - op1 + carry - 1
  if op.s:
    cpu.airthmeticFlags(op.rd, r, op2, op1)
  cpu.reg(op.rd) = r

func opTst(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0b1000
  ## same as AND, but result isn't written
  var
    shiftCarry = psC in cpu.cpsr
  let
    (op1, op2) = op.operands(cpu, shiftCarry)
    r = op1 and op2
  if op.s:
    cpu.logicFlags(op.rd, r, shiftCarry)

func opTeq(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0b1001
  ## same as EOR, but result isn't written
  var
    shiftCarry = psC in cpu.cpsr
  let
    (op1, op2) = op.operands(cpu, shiftCarry)
    r = op1 xor op2
  if op.s:
    cpu.logicFlags(op.rd, r, shiftCarry)

func opCmp(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 1010
  ## same as SUB, but result isn't written
  let
    (op1, op2) = op.operands(cpu)
    r = op1 - op2
  if op.s:
    cpu.airthmeticFlags(op.rd, r, op1, op2)

func opCmn(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0101
  ## same as ADD, but result isn't written
  let
    (op1, op2) = op.operands(cpu)
    r = op1 + op2
  if op.s:
    cpu.airthmeticFlags(op.rd, r, op1, op2)

func opOrr(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 1100
  ## Rd := Operand1 OR Operand2
  var
    shiftCarry = psC in cpu.cpsr
  let
    (op1, op2) = op.operands(cpu, shiftCarry)
    r = op1 or op2
  if op.s:
    cpu.logicFlags(op.rd, r, shiftCarry)
  cpu.reg(op.rd) = r

func opMov(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0b1101
  ## Rd := Operand2
  var
    shiftCarry = psC in cpu.cpsr
  let
    value = op.operand2.value(cpu, shiftCarry)
  if op.s:
    cpu.logicFlags(op.rd, value, shiftCarry)
  cpu.reg(op.rd) = value
  # TODO: this should be handled in a central place somewhere
  if op.rd == 15:
    cpu.reg(op.rd) += ArmInstructionSize*2

func opBic(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 0b1110
  ## Rd := Operand1 AND NOT Operand2
  var
    shiftCarry = psC in cpu.cpsr
  let
    (op1, op2) = op.operands(cpu, shiftCarry)
    r = op1 and (not op2)
  if op.s:
    cpu.logicFlags(op.rd, r, shiftCarry)
  cpu.reg(op.rd) = r

func opMvn(cpu: var Arm7tdmiState, op: OpAlu) =
  ## OpCode: 1111
  ## Rd := not Operand2
  var
    shiftCarry = psC in cpu.cpsr
  let
    (_, op2) = op.operands(cpu, shiftCarry)
    r = not op2
  if op.s:
    cpu.logicFlags(op.rd, r, shiftCarry)
  cpu.reg(op.rd) = r



type
  AddressingMode = enum
    adPostDown = 0b00
    adPostUp   = 0b01
    adPreDown  = 0b10
    adPreUp    = 0b11

  AddressingIterator = iterator(): MemAddress
  AddressingIter = proc(base: MemAddress): AddressingIterator

const
  AddressingModes: array[AddressingMode, AddressingIter] = [
    # Post down
    proc(base: MemAddress): AddressingIterator {.closure.} =
      result = iterator(): MemAddress =
        var address = base
        while true:
          yield address
          address -= ArmInstructionSize
          yield address
    ,
    # Post up
    proc(base: MemAddress): AddressingIterator {.closure.} =
      result = iterator(): MemAddress =
        var address = base
        while true:
          yield address
          address += ArmInstructionSize
          yield address
    ,
    # Pre down
    proc(base: MemAddress): AddressingIterator {.closure.} =
      result = iterator(): MemAddress =
        var address = base
        while true:
          address -= ArmInstructionSize
          yield address
          yield address
    ,
    # Pre up
    proc(base: MemAddress): AddressingIterator {.closure.} =
      result = iterator(): MemAddress =
        var address = base
        while true:
          address += ArmInstructionSize
          yield address
          yield address
  ]



func opSingleDataTransfer(cpu: var Arm7tdmiState, instr: ArmInstruction, mem: Mcu) =
  if not instr.checkCondition(cpu):
    return

  let
    isImmediate = instr.i
    isPre = instr.testBit(24)
    isUp = instr.testBit(23)
    isByte = instr.testBit(22)
    shouldWriteBack = instr.testBit(21)
    isLoad = instr.testBit(20)
    rn = instr.rn
    rd = instr.rd
  
  assert not isPre and not shouldWriteBack, "LDR/STR: for post-indexed instructions W has to be 0"
  
  var
    offset =
      if isImmediate:
        instr.extract(0, 11).int
      else:
        let
          rm = instr.rm
        assert rm != 15, "LDR/STR: R15 must not be specified as Rm"
        # TODO: calculate register based shift
        0
  if not isUp:
    offset = -offset
  
  var
    address = cpu.reg(rn)
  if isPre:
    address = (address.int + offset).uint32

  if isLoad:
    if isByte:
      cpu.reg(rd) = mem.read[:uint8](address)
    else:
      cpu.reg(rd) = mem.read[:uint16](address)
  else:
    if isByte:
      mem.write[:uint8](address, cpu.reg(rd).uint8)
    else:
      mem.write[:uint16](address, cpu.reg(rd).uint16)

  # TODO: do memory load/store
  if not isPre:
    address = (address.int + offset).uint32
  if shouldWriteBack or not isPre:
    cpu.reg(rn) = address
  
  #[ TODO: cycles
  LDR     1S + 1N + 1I
  LDR PC  2S + 2N +1I
  STR     2N
  ]#



proc opBlockDataTransfer(cpu: var Arm7tdmiState, instr: ArmInstruction, mem: Mcu) =
  ## Block Data Transfer (LDM, STM)
  ##
  ## See: Page 56
  if not instr.checkCondition(cpu):
    return

  let
    isPre = ((not instr.testBit(24)).int shl 1) + 1
    isUp = instr.testBit(23)
    # TODO: implement the S flag [bit 22]
    isWriteBack = instr.testBit(21)
    isLoad = instr.testBit(20)
    rn = instr.extract(16, 19).int
    registers = cast[set[Register]](instr.extract(0, 15).uint16)

  var
    base = cpu.reg(rn)
  if not isUp:
    base -= registers.card.uint32 * ArmInstructionSize
    if isWriteBack:
      cpu.reg(rn) = base

  let
    addressCalc = AddressingModes[isPre.AddressingMode](cpu.reg(rn))
  var
    address: MemAddress
  for r in registers:
    address = addressCalc()
    # TODO: maybe this should be moved into a different handler?
    if isLoad:
      cpu.reg(r.ord) = mem.read[:uint32](address)
    else:
      mem.write[:uint32](address, cpu.reg(r.ord))
    address = addressCalc()
  
  if isWriteBack and isUp:
    cpu.reg(rn) = address



func opHalfDataTransfer(cpu: var Arm7tdmiState, instr: ArmInstruction, mem: Mcu) =
  ## Halfword and Signed Data Transfer (LDRH, STRH, LDRSB, LDRSH)
  ##
  ## See: Page 52 [58]
  discard



func opMsr(cpu: var Arm7tdmiState, instr: ArmInstruction, mem: Mcu) =
  ## PSR Transfer (MRS, MSR)
  ## 
  ## See: Page 40 [46]
  let
    isImmediate = instr.testBit(25)
    onlyFlags = not instr.testBit(16)
    dest = instr.testBit(22)
  assert onlyFlags or not isImmediate, "MSR: Immediate value only supported for the flag only version"

  var
    value =
      if isImmediate:
        instr.operandImmediate()
      else:
        assert instr.extract(4, 11) == 0
        let
          r = instr.extract(0, 3)
        assert r != 15, "MSR: R15 isn't supported as the destination register"
        cpu.reg(r)
  if onlyFlags:
    value = value and 0xf0000000'u32
  
  if dest:
    cpu.spsr[] = value
  else:
    cpu.cpsr = value





proc step*(state: var Arm7tdmiState, mem: Mcu) =
  let
    instr = mem.read[:uint32](state.pc - 2*ArmInstructionSize)

  echo &"{state.pc.int - 8:#010x}\t{instr.int:#010x} {instr.int:#034b}"
  let
    op = instr.decode[:ArmOp]()
  state.pc += ArmInstructionSize

  if op.checkCondition(state):
    case op.kind
    of omBX:
      state.opArmBx(instr)
    of omB:
      state.opArmB(instr)
    of omLDM, omSTM:
      state.opBlockDataTransfer(op.instr, mem)
    of omLDRH, omSTRH, omLDRSB, omLDRSH:
      state.opHalfDataTransfer(op.instr, mem)
    of omMRS, omMSR:
      state.opMsr(op.instr, mem)
    of omAND: state.opAnd(op.alu)
    of omEOR: state.opEor(op.alu)
    of omSUB: state.opSub(op.alu)
    of omRSB: state.opRsb(op.alu)
    of omADD: state.opAdd(op.alu)
    of omADC: state.opAdc(op.alu)
    of omSBC: state.opSbc(op.alu)
    of omRSC: state.opRsc(op.alu)
    of omTST: state.opTst(op.alu)
    of omTEQ: state.opTeq(op.alu)
    of omCMP: state.opCmp(op.alu)
    of omCMN: state.opCmn(op.alu)
    of omORR: state.opOrr(op.alu)
    of omMOV: state.opMov(op.alu)
    of omBIC: state.opBic(op.alu)
    of omMVN: state.opMvn(op.alu)
    of omLDR, omSTR:
      state.opSingleDataTransfer(op.instr, mem)
    else:
      assert false, &"Unrecognized instruction: {state.pc.int - 8}\t{instr.int:#010x} {instr.int:#034b}"
  echo "\t\t", op
  echo state
  