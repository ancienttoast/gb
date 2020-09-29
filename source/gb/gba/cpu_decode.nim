import
  std/strformat,
  gb/common/util



type
  ArmInstruction* = uint32
  ThumbInstruction* = uint16

  Condition* = enum
    cEQ = 0b0000    ## equal                      Z set
    cNE = 0b0001    ## not equal                  Z clear
    cCS = 0b0010    ## unsigned higher or same    C set
    cCC = 0b0011    ## unsigned lower             C clear
    cMI = 0b0100    ## negative                   N set
    cPL = 0b0101    ## positive or zero           N clear
    cVS = 0b0110    ## overflow                   V set
    cVC = 0b0111    ## no overflow                V clear
    cHI = 0b1000    ## unsigned higher            C set and Z clear
    cLS = 0b1001    ## unsigned lower or same     C clear or Z set
    cGE = 0b1010    ## greater or equal           N equals V
    cLT = 0b1011    ## less than                  N not equal to V
    cGT = 0b1100    ## greater than               Z clear AND (N equals V)
    cLE = 0b1101    ## less than or equal         Z set OR (N not equal to V)
    cAL = 0b1110    ## always                     (ignored)

  OpMnemonic* = enum
    omAND, omEOR, omSUB, omRSB, omADD, omADC, omSBC, omRSC, omTST, omTEQ, omCMP, omCMN, omORR, omMOV, omBIC, omMVN
    omB, omBX
    omCDP
    omLDC
    omLDM, omSTM
    omLDR, omSTR
    omLDRH, omSTRH, omLDRSB, omLDRSH
    omMCR
    omMLA
    omMRC
    omMRS, omMSR
    omMUL
    omSTC
    omSWI
    omSWP
  
  Register* = range[0..15]

  OpAluOperand* = object
    case isImmediate*: bool
    of true:
      rotate*: uint
      imm*: uint32
    of false:
      shift*: uint32
      rm*: int

  OpAlu* = object
    s*: bool
    rn*: Register
    rd*: Register
    operand2*: OpAluOperand
  
  ArmOp* = object
    condition*: Condition
    case kind*: OpMnemonic
    of omAND..omMVN:
      alu*: OpAlu
    else:
      # TODO: parse these as well
      instr*: ArmInstruction



#[

    ALU instructions

]#
proc decode*[T](instr: ArmInstruction): T {.inline.}

proc decode(instr: ArmInstruction, op: var OpAluOperand) =
  let
    i = instr.testBit(25)
  op =
    if i:
      OpAluOperand(
        isImmediate: true,
        rotate: instr.extract(8, 11),
        imm: instr.extract(0, 7)
      )
    else:
      OpAluOperand(
        isImmediate: false,
        shift: instr.extract(4, 11),
        rm: instr.extract(0, 3).int
      )

proc decode(instr: ArmInstruction, op: var OpAlu) =
  op = OpAlu(
    s: instr.testBit(20),
    rn: instr.extract(16, 19).int,
    rd: instr.extract(12, 15).int
  )
  instr.decode(op.operand2)

proc decode(instr: ArmInstruction, op: var ArmOp) =
  if (instr and 0b0000_1111_1111_1111_1111_1111_1111_0000) == 0b0000_0001_0010_1111_1111_1111_0001_0000:
    op = ArmOp(
      kind: omBX,
      instr: instr
    )
  elif (instr and 0b0000_1010_0000_0000_0000_0000_0000_0000) == 0b0000_1010_0000_0000_0000_0000_0000_0000:
    op = ArmOp(
      kind: omB,
      instr: instr
    )
  elif (instr and 0b0000_1110_0000_0000_0000_0000_0000_0000) == 0b0000_1000_0000_0000_0000_0000_0000_0000:
    # Block Data Transfer (LDM, STM)
    op = ArmOp(
      kind: omLDM,
      instr: instr
    )
  elif (instr and 0b0000_1110_0000_0000_0000_0000_1001_0000) == 0b0000_0000_0000_0000_0000_0000_1001_0000:
    # Halfword and Signed Data Transfer (LDRH, STRH, LDRSB, LDRSH)
    op = ArmOp(
      kind: omLDRH,
      instr: instr
    )
  elif (instr and 0b0000_1101_1011_1111_1111_0000_0000_0000) == 0b0000_0001_0010_1000_1111_0000_0000_0000 or
    (instr and 0b0000_1111_1011_1111_1111_1111_1111_0000) == 0b0000_0001_0010_1001_1111_0000_0000_0000:
    # PSR Transfer (MRS, MSR)
    op = ArmOp(
      kind: omMRS,
      instr: instr
    )
  else:
    case instr.extract(26, 27)
    of 0b00:
      op = ArmOp(kind: instr.extract(21, 24).OpMnemonic)
      assert op.kind in { omAND..omMVN }
      op.alu = instr.decode[:OpAlu]()
    of 0b10:
      # Single Data Transfer (LDR, STR)
      op = ArmOp(
        kind: omLDR,
        instr: instr
      )
    else:
      assert false, "Unrecognized instruction"

  op.condition = (instr shr 28).Condition

proc decode*[T](instr: ArmInstruction): T {.inline.} =
  instr.decode(result)


proc `$`(mnemoic: OpMnemonic): string =
  system.`$`(mnemoic).substr(2)

proc `$`(cond: Condition): string =
  if cond == cAL:
    ""
  else:
    system.`$`(cond).substr(1)

proc `$`*(op: ArmOp): string =
  case op.kind
  of omMOV, omMVN:
    let
      alu = op.alu
      s = if alu.s: "S" else: ""
    &"{op.kind}{op.condition}{s} R{alu.rd},<Op2>"
  of omCMP, omCMN, omTEQ, omTST:
    let
      alu = op.alu
    &"{op.kind}{op.condition} R{alu.rd},<Op2>"
  of omAND, omEOR, omSUB, omRSB, omADD, omADC, omSBC, omRSC, omORR, omBIC:
    let
      alu = op.alu
    &"{op.kind}{op.condition} R{alu.rd},R{alu.rn},<Op2>"
  else:
    &"{op.kind}"