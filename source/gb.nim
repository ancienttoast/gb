##[

  Gameboy models:
    DMG   Game Boy
    MGB   Game Boy Pocket
    SGB   Super Game Boy
    SGB2  Super Game Boy 2
    CGB   Game Boy Color

]##
import
  mem, cpu, timer, display, cartridge



type
  Gameboy = object
    mcu: Mcu
    cpu: Cpu
    timer: Timer
    display: Display

proc initGameboy(): Gameboy =
  Gameboy(
    mcu: newMcu(),
    cpu: initCpu(),
    timer: newTimer(),
    display: newDisplay()
  )


const
  bootRom = readFile("123/[BIOS] Nintendo Game Boy Boot ROM (World).gb")
let
  bootRomHandler = MemHandler(
    read: proc(address: MemAddress): uint8 = cast[uint8](bootRom[address.int]),
    write: proc(address: MemAddress, value: uint8) = discard,
    area: 0.MemAddress ..< 256.MemAddress
  )
  bootRomDisableHandler = MemHandler(
    read: proc(address: MemAddress): uint8 = 0,
    write: proc(address: MemAddress, value: uint8) =
      debugEcho "DISABLE BOOT ROM"
    ,
    area: 0xff50.MemAddress ..< 0xff50.MemAddress
  )
assert bootRom.len == 256

var
  testMemory = newSeq[uint8](uint16.high.int + 1)


var
  gameboy = initGameboy()
  cart = initCartridge("123/Tetris (World) (Rev A).gb")
gameboy.mcu.pushHandler(0, addr testMemory)
gameboy.timer.register(gameboy.mcu)
gameboy.display.register(gameboy.mcu)

gameboy.mcu.pushHandlers(initMbcNone(addr cart.data))
gameboy.mcu.pushHandler(bootRomHandler)
gameboy.mcu.pushHandler(bootRomDisableHandler)

var
  wait = false
try:
  while testMemory[0xff50] != 1:# and gameboy.cpu.pc < 0x00e9:
    #if wait:
    #  discard stdin.readLine()
    gameboy.timer.step()
    gameboy.cpu.step(gameboy.mcu)
    if gameboy.cpu.pc > 0x001f'u16:
      wait = true
except:
  echo getCurrentException().msg
  echo getStackTrace(getCurrentException())
  echo "cpu\t", gameboy.cpu.state
  echo "display\t", gameboy.display.state
