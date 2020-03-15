#[

  Header

    0100-0103 - Entry Point
    0104-0133 - Nintendo Logo
    0134-0143 - Title
      013F-0142 - Manufacturer Code
      0143 - CGB Flag
    0144-0145 - New Licensee Code
    0146 - SGB Flag
    0147 - Cartridge Type
    0148 - ROM Size
    0149 - RAM Size
    014A - Destination Code
    014B - Old Licensee Code
    014C - Mask ROM Version number
    014D - Header Checksum
    014E-014F - Global Checksum

]#
import
  mem



type
  CartridgeType = enum
    ctRom = 0x00
    ctMbc1 = 0x01
    ctMbc1Ram = 0x02
    ctMbc1RamBattery = 0x03
    ctMbc2 = 0x05
    ctMbc2Battery = 0x06
    ctRomRam = 0x08
    ctRomRamBattery = 0x09
    ctMMM01 = 0x0b
    ctMMM01Ram = 0x0c
    ctMMM01RamBattery = 0x0d
    ctMbc3TimerBattery = 0x0f
    ctMbc3TimerRamBattery = 0x10
    ctMbc3 = 0x11
    ctMbc3Ram = 0x12
    ctMbc3RamBattery = 0x13
    ctMbc5 = 0x19
    ctMbc5Battery = 0x1a
    ctMbc5RamBattery = 0x1b
    ctMbc5Rumble = 0x1c
    ctMbc5RumbleRam = 0x1d
    ctMbc5RumbleRamBattery = 0x1e
    ctMbc6 = 0x20
    ctMbc7SensorRumbleRamBattery = 0x22
    ctPocketCamera = 0xfc
    ctBandaiTamas = 0xfd
    ctHuc3 = 0xfe
    ctHuc1RamBattery = 0xff
  
  CartridgeRomSize = enum
    crs32KByte  = 0x00 # 32KByte (no ROM banking)
    crs64KByte  = 0x01 # 64KByte (4 banks)
    crs128KByte = 0x02 # 128KByte (8 banks)
    crs256KByte = 0x03 # 256KByte (16 banks)
    crs512KByte = 0x04 # 512KByte (32 banks)
    crs1MByte   = 0x05 # 1MByte (64 banks)  - only 63 banks used by MBC1
    crs2MByte   = 0x06 # 2MByte (128 banks) - only 125 banks used by MBC1
    crs4MByte   = 0x07 # 4MByte (256 banks)
    crs8MByte   = 0x08 # 8MByte (512 banks)
    crs11MByte  = 0x52 # 1.1MByte (72 banks)
    crs12MByte  = 0x53 # 1.2MByte (80 banks)
    crs15MByte  = 0x54 # 1.5MByte (96 banks)
  
  CartridgeRamSize = enum
    crsNone      = 0x00
    crs2KBytes   = 0x01 # 2 KBytes
    crs8Kbytes   = 0x02 # 8 Kbytes
    crs32KBytes  = 0x03 # 32 KBytes (4 banks of 8KBytes each)
    crs128KBytes = 0x04 # 128 KBytes (16 banks of 8KBytes each)
    crs64KBytes  = 0x05 # 64 KBytes (8 banks of 8KBytes each)


const
  # TODO: use CartridgeRomSize somehow
  RomSize: array[0..11, int] = [ 32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 1179648, 1310720, 1572864 ]
  RamSize: array[CartridgeRamSize, int] = [ 0, 2048, 8192, 32768, 131072, 65536 ]

const
  HeaderArea = 0x0100..0x014f



const
  CartridgeStartAddress = 0

type
  Mbc = seq[MemHandler]

proc initMbcNone(data: ptr string): Mbc =
  assert data[].len == 32768
  result = newSeq[MemHandler]()
  result &= MemHandler(
    read: proc(address: MemAddress): uint8 =
      cast[uint8](data[address.int]),
    write: proc(address: MemAddress, value: uint8) =
      discard,
    area: CartridgeStartAddress.MemAddress ..< 32768.MemAddress
  )



type
  Cartridge* = ref object
    data*: string
    mbc: Mbc

proc initCartridge*(file: string): Cartridge =
  let
    data = readFile(file)
  assert (data[0x0147].CartridgeType == ctRom or data[0x0147].CartridgeType == ctMbc1) and
    data[0x0148].CartridgeRomSize == crs32KByte and
    data[0x0149].CartridgeRamSize == crsNone

  result = Cartridge(
    data: data
  )
  result.mbc = initMbcNone(addr result.data)

proc pushHandlers*(mcu: var Mcu, cart: Cartridge) =
  for handler in cart.mbc:
    mcu.pushHandler(handler)
