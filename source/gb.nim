##[

  Gameboy models:
    DMG   Game Boy
    MGB   Game Boy Pocket
    SGB   Super Game Boy
    SGB2  Super Game Boy 2
    CGB   Game Boy Color

]##
import
  gb/[mem, cpu, timer, display, cartridge]



type
  Gameboy* = ref object
    mcu*: Mcu
    cpu*: Cpu
    timer*: Timer
    display*: Display

    cart*: Cartridge
    bootRom*: string
    testMemory*: seq[uint8]

proc load(self: Gameboy) =
  self.bootRom = readFile("123/[BIOS] Nintendo Game Boy Boot ROM (World).gb")
  let
    bootRomHandler = MemHandler(
      read: proc(address: MemAddress): uint8 = cast[uint8](self.bootRom[address.int]),
      write: proc(address: MemAddress, value: uint8) = discard,
      area: 0.MemAddress ..< 256.MemAddress
    )
    bootRomDisableHandler = MemHandler(
      read: proc(address: MemAddress): uint8 = 0,
      write: proc(address: MemAddress, value: uint8) =
        self.mcu.popHandler()
        self.mcu.popHandler()
      ,
      area: 0xff50.MemAddress .. 0xff50.MemAddress
    )
  assert self.bootRom.len == 256

  self.testMemory = newSeq[uint8](uint16.high.int + 1)

  self.cart = initCartridge("123/bgbw64/bgbtest.gb")
  self.mcu.clearHandlers()
  self.mcu.pushHandler(0, addr self.testMemory)
  self.mcu.pushHandler(self.cpu)
  self.mcu.pushHandler(self.timer)
  self.mcu.pushHandler(self.display)
  
  self.mcu.pushHandlers(initMbcNone(addr self.cart.data))
  self.mcu.pushHandler(bootRomHandler)
  self.mcu.pushHandler(bootRomDisableHandler)

proc newGameboy*(): Gameboy =
  let
    mcu = newMcu()
  result = Gameboy(
    mcu: mcu,
    cpu: newCpu(mcu),
    timer: newTimer(mcu),
    display: newDisplay(mcu)
  )
  result.load()



when isMainModule:
  proc main() =
    var
      gameboy = newGameboy()
    try:
      while gameboy.testMemory[0xff50] != 1:
        gameboy.cpu.step(gameboy.mcu)
        gameboy.timer.step()
        gameboy.display.step()
    except:
      echo getCurrentException().msg
      echo getStackTrace(getCurrentException())
      echo "cpu\t", gameboy.cpu.state
      echo "display\t", gameboy.display.state

    gameboy.display.renderTiles(0).savePNG("block0.png")
    gameboy.display.renderTiles(1).savePNG("block1.png")
    gameboy.display.renderTiles(2).savePNG("block2.png")

  main()
