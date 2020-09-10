import
  mem, bitops



type
  Interrupt* {.size: sizeof(uint8).} = enum
    iVBlank   ## [INT 0x40]
    iLcdStat  ## [INT 0x48]
    iTimer    ## [INT 0x50]
    iSerial   ## [INT 0x58]
    iJoypad   ## [INT 0x60]

const
  InterruptHandler*: array[Interrupt, MemAddress] = [ 0x40.MemAddress, 0x48, 0x50, 0x58, 0x60 ]
  IfAddress = 0xff0f.MemAddress

proc raiseInterrupt*(mcu: Mcu, interrupt: Interrupt) =
  var
    table = mcu[IfAddress]
  setBit(table, interrupt.ord)
  mcu[IfAddress] = table
