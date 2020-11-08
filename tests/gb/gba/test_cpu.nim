import
    std/unittest,
    gb/gba/[mem, cpu]



proc initCpu(): Arm7tdmiState =
  result.reg(0) = 0x00000ca5
  result.reg(13) = 0x03007f00
  result.reg(14) = 0x08000000
  result.pc = 0x08000000
  result.cpsr = cast[ProgramStatusRegister](0x0000001f)
  result.mode = mSystem

suite "unit.gba.cpu: ARM7TDMI - arm: branch instructions":
  test "B +c0":
    var
      data = newSeq[uint8](33_554_432)
      cpu = initCpu()
    let
      mcu = newMcu()
    mcu.setHandler(msGamePakRom0, addr data)
    mcu.write[:uint32](0x08000000, 0xea00002e'u32)

    cpu.step(mcu)

    check cpu.pc == (0x080000c0 + 8)
  
  test "B +0":
    var
      data = newSeq[uint8](33_554_432)
      cpu = initCpu()
    let
      mcu = newMcu()
    mcu.setHandler(msGamePakRom0, addr data)
    mcu.write[:uint32](0x08000000, 0xea000000'u32)

    cpu.step(mcu)

    check cpu.pc == (0x08000008 + 8)

  test "B -8":
    var
      data = newSeq[uint8](33_554_432)
      cpu = initCpu()
    let
      mcu = newMcu()
    mcu.setHandler(msGamePakRom0, addr data)
    mcu.write[:uint32](0x08000000, 0xeafffffe'u32)

    cpu.step(mcu)

    check cpu.pc == 0x08000008