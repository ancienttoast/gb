import
  std/[streams, strutils],
  gb/common/util,
  gb/gba/[cart, cpu, mem]



let
  data = readFile("arm.gba")
  s = newStringStream(data)
var
  header: CartHeader
discard s.readData(addr header, sizeof CartHeader)

echo header
echo ""
echo ""

proc initGamePakHandler(data: string, base: MemAddress): MemHandler =
  MemHandler(
    read: proc(address: MemAddress): uint8 =
      let
        i = (address - base).int
      if i < data.len:
        data[i].uint8
      else:
        0
    ,
    write: proc(address: MemAddress, value: uint8) = discard
  )



var
  memBios = newSeq[uint8](16_384)
  memWramOnBoard = newSeq[uint8](262_144)
  memWramOnChip = newSeq[uint8](32_768)
  memIo = newSeq[uint8](1_023)
  memVPalette = newSeq[uint8](1_024)
  memVRam = newSeq[uint8](98_304)
  memVObj = newSeq[uint8](1_024)
  memCartSram = newSeq[uint8](65_536)
let
  mcu = newMcu()
mcu.setHandler(msBios, addr memBios)
mcu.setHandler(msWramOnBoard, addr memWramOnBoard)
mcu.setHandler(msWramOnChip, addr memWramOnChip)
mcu.setHandler(wsIO, addr memIo)

mcu.setHandler(msVPaletteRam, addr memVPalette)
mcu.setHandler(msVram, addr memVRam)
mcu.setHandler(msVObj, addr memVObj)

mcu.setHandler(msGamePakRom0, initGamePakHandler(data, 0x08000000))
mcu.setHandler(msGamePakRom1, initGamePakHandler(data, 0x0a000000))
mcu.setHandler(msGamePakRom2, initGamePakHandler(data, 0x0c000000))
mcu.setHandler(msGamePakSram, addr memCartSram)


var
  cpuState: Arm7tdmiState
# Initial state: probably set by the bios
cpuState.reg(0) = 0x00000ca5
cpuState.reg(13) = 0x03007f00
cpuState.reg(14) = 0x08000000
cpuState.pc = 0x08000000
cpuState.cpsr = cast[ProgramStatusRegister](0x0000001f)
cpuState.mode = mSystem

try:
  while true:
    cpuState.step(mcu)
    if cpuState.pc >= 0x10000000:
      quit(0)
except:
  echo cpuState
  echo getCurrentExceptionMsg()
  echo getStackTrace(getCurrentException())
