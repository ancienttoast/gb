import
  std/streams



type
  CartridgeType* {.size: sizeof(uint8).} = enum
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
  
  CartridgeRomSize* {.size: sizeof(uint8).} = enum
    crs32KByte  = 0x00  ## 32KByte (no ROM banking)
    crs64KByte  = 0x01  ## 64KByte (4 banks)
    crs128KByte = 0x02  ## 128KByte (8 banks)
    crs256KByte = 0x03  ## 256KByte (16 banks)
    crs512KByte = 0x04  ## 512KByte (32 banks)
    crs1MByte   = 0x05  ## 1MByte (64 banks)  - only 63 banks used by MBC1
    crs2MByte   = 0x06  ## 2MByte (128 banks) - only 125 banks used by MBC1
    crs4MByte   = 0x07  ## 4MByte (256 banks)
    crs8MByte   = 0x08  ## 8MByte (512 banks)
    crs11MByte  = 0x52  ## 1.1MByte (72 banks)
    crs12MByte  = 0x53  ## 1.2MByte (80 banks)
    crs15MByte  = 0x54  ## 1.5MByte (96 banks)
  
  CartridgeRamSize* {.size: sizeof(uint8).} = enum
    crsNone      = 0x00  ## No RAM
    crs2KBytes   = 0x01  ## 2 KBytes
    crs8Kbytes   = 0x02  ## 8 Kbytes
    crs32KBytes  = 0x03  ## 32 KBytes (4 banks of 8KBytes each)
    crs128KBytes = 0x04  ## 128 KBytes (16 banks of 8KBytes each)
    crs64KBytes  = 0x05  ## 64 KBytes (8 banks of 8KBytes each)

  CartHeader* = tuple
    entryPoint:     uint32            ## 0x0100  Entrypoint
    logo:           array[48, uint8]  ## 0x0104  Logo
    title:          array[11, char]   ## 0x0134  Title
    manufacturer:   array[4, char]    ## 0x013f  Manufacturer Code
    cgb:            uint8             ## 0x0143  CGB Flag
    newLicensee:    array[2, char]    ## 0x0144  New Licensee Code
    sgb:            uint8             ## 0x0146  SGB Flag
    kind:           CartridgeType     ## 0x0147  Cartridge Type
    romSize:        CartridgeRomSize  ## 0x0148  ROM Size
    ramSize:        CartridgeRamSize  ## 0x0149  RAM Size
    destination:    uint8             ## 0x014a  Destination Code
                                      ##   0x00 - Japanese
                                      ##   0x01 - Non-Japanese
    oldLicensee:    uint8             ## 0x014b  Old Licensee Code
                                      ##   A value of 0x33 means the `newLicensee` code is used instead.
    version:        uint8             ## 0x014c  Mask ROM Version Number
    headerChecksum: uint8             ## 0x014d  Header Checksum
    globalChecksum: uint16            ## 0x014e  Global Checksum


const
  RomBankSize* = 16_384
  RamBankSize* = 8_192
  # TODO: use CartridgeRomSize somehow
  #RomSize: array[0..11, int] = [ 32_768, 65_536, 131_072, 262_144, 524_288, 1_048_576, 2_097_152, 4_194_304, 8_388_608, 1_179_648, 1_310_720, 1_572_864 ]
  RamSize*: array[CartridgeRamSize, int] = [ 0, 2_048, 8_192, 32_768, 131_072, 65_536 ]


proc readCartHeader*(data: string): CartHeader =
  let
    stream = newStringStream(data)
  stream.setPosition(0x0100)
  let
    read = stream.readData(addr result, sizeof(CartHeader))
  stream.close()
  assert read == sizeof(CartHeader)

func isCgb*(self: CartHeader): bool =
  self.cgb == 0x80 or self.cgb == 0xc0