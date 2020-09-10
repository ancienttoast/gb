type
  CartHeader* = tuple
    romEntry: uint32 ## ROM Entry Point  (32bit ARM branch opcode, eg. "B rom_start")
    logo: array[156, uint8] ## Nintendo Logo    (compressed bitmap, required!)
    title: array[12, char] ## Game Title       (uppercase ascii, max 12 characters)
    gameCode: array[4, char] ## Game Code        (uppercase ascii, 4 characters)
    makerCode: uint16 ## Maker Code       (uppercase ascii, 2 characters)
    landmark: uint8 ## Fixed value      (must be 96h, required!)
    unitCode: uint8 ## Main unit code   (00h for current GBA models)
    device: uint8 ## Device type      (usually 00h) (bit7=DACS/debug related)
    reserved0: array[7, uint8] ## Reserved Area    (should be zero filled)
    version: uint8 ## Software version (usually 00h)
    complement: uint8 ## Complement check (header checksum, required!)
    reserved1: array[2, uint8] ## Reserved Area    (should be zero filled)
  
  CartMultibootHeader = tuple
    ramEntry: uint32 ## RAM Entry Point  (32bit ARM branch opcode, eg. "B ram_start")
    bootMode: uint8 ## Boot mode        (init as 00h - BIOS overwrites this value!)
    slaveId: uint8 ## Slave ID Number  (init as 00h - BIOS overwrites this value!)
    unused: array[26, uint8] ## Not used         (seems to be unused)
    joyEntry: uint32 ## JOYBUS Entry Pt. (32bit ARM branch opcode, eg. "B joy_start")
