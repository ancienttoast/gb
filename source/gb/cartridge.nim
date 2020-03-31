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
  RomBankSize = 16_384
  RamBankSize = 8_192
  # TODO: use CartridgeRomSize somehow
  RomSize: array[0..11, int] = [ 32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 1179648, 1310720, 1572864 ]
  RamSize: array[CartridgeRamSize, int] = [ 0, 2048, 8192, 32_768, 131_072, 65_536 ]

const
  HeaderArea = 0x0100..0x014f



const
  CartridgeStartAddress = 0

type
  MbcState = tuple
    rom: uint8
    ram: int

proc initMbcNone(mcu: Mcu, state: ptr MbcState, data: ptr string) =
  assert data[].len == 32768
  let
    handler = MemHandler(
      read: proc(address: MemAddress): uint8 =
        cast[uint8](data[address.int]),
      write: proc(address: MemAddress, value: uint8) =
        discard,
      area: CartridgeStartAddress.MemAddress ..< 0x7fff.MemAddress
    )
  mcu.pushHandler(handler)

proc initMbcOne(mcu: Mcu, state: ptr MbcState, data: ptr string, ramSize: CartridgeRamSize) =
  state.rom = 1
  var
    # TODO: move to the MbcState
    select = 0
    ramEnable = false
    ram = newSeq[uint8](RamSize[ramSize])
  let
    romHandler = MemHandler(
      read: proc(address: MemAddress): uint8 =
        if address in 0x0000'u16..0x3fff'u16:
          cast[uint8](data[address.int])
        else:
          let
            p = address - 0x4000
          cast[uint8](data[(state.rom.int * RomBankSize) + p.int])
      ,
      write: proc(address: MemAddress, value: uint8) =
        case address
        of 0x0000'u16-0x1fff'u16:
          ramEnable = ramSize != crsNone and (value and 0x0f) == 0x0a
        of 0x2000'u16..0x3fff'u16:
          state.rom = state.rom and 0b11100000
          state.rom = state.rom or (value and 0b00011111)
          # TODO
          if state.rom == 0:
            state.rom = 1
        of 0x4000'u16..0x5fff'u16:
          if select == 0:
            state.rom = state.rom and 0b00011111
            state.rom = state.rom or (value and 0b00000011 shl 5)
          else:
            state.ram = (value and 0b00000011 shl 5).int
        of 0x6000'u16..0x7fff'u16:
          assert value in {0, 1}
          select = value.int
        else:
          discard
      ,
      area: CartridgeStartAddress.MemAddress ..< 0x7fff.MemAddress
    )
    ramHandler = MemHandler(
      read: proc(address: MemAddress): uint8 =
        if not ramEnable:
          return 0
        let
          p = (state.ram.int * RomBankSize) + (address.int - 0xa000)
        if p > ram.high:
          0'u8
        else:
          ram[p]
      ,
      write: proc(address: MemAddress, value: uint8) =
        if not ramEnable:
          return
        let
          p = (state.ram.int * RomBankSize) + (address.int - 0xa000)
        if p <= ram.high:
          ram[p] = value
      ,
      area: 0xa000'u16..0xbfff'u16
    )
  mcu.pushHandler(romHandler)
  mcu.pushHandler(ramHandler)



type
  Cartridge* = ref object
    kind: CartridgeType
    romSize: CartridgeRomSize
    ramSize: CartridgeRamSize
    data*: string
    state: MbcState

proc initCartridge*(file: string): Cartridge =
  let
    data = readFile(file)
  result = Cartridge(
    data: data,
    kind: data[0x0147].CartridgeType,
    romSize: data[0x0148].CartridgeRomSize,
    ramSize: data[0x0149].CartridgeRamSize
  )

proc pushHandlers*(mcu: Mcu, cart: Cartridge) =
  case cart.kind:
  of ctRom:
    mcu.initMbcNone(addr cart.state, addr cart.data)
  of ctMbc1, ctMbc1Ram, ctMbc1RamBattery:
    mcu.initMbcOne(addr cart.state, addr cart.data, cart.ramSize)
  else:
    assert false, "Unsupported cartridge type " & $cart.kind
