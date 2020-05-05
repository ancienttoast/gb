##[

  Video Ppu
  ===========================

  160x144

  Memory map
  ----------

  0xff40  LCDC LCD Control Register
  0xff47-0xff49  Monochrome palettes - Non CGB mode only
    0xff47  BGP  - BG Palette (R/W)
    0xff48  OBP0 - Object Palette 0 (R/W)
    0xff49  OBP1 - Object Palette 1 (R/W)
  
  0x8000-0x9fff  VRAM
    0x8000-0x97ff  Tile Data
      0x8000-0x87ff  Block 0
      0x8800-0x8fff  Block 1
      0x9000-0x97ff  Block 2
    0x9800-0x9bff  BG Map 0
    0x9c00-0x9fff  BG Map 1
  0xfe00-0xfe9f  OAM

  Single line of pixels (fixed 456 cycles)

              2222 3333333
    Scan Line  ----------->
              000000000000
    H Blank    <-----------

    Mode 2  80 cycles (2 cycles per entry in OAM)
    Mode 3  Variable length (168 to 291)
    Mode 0  Variable length, whatever it takes to reach 456 cycles
    Mode 1  456 * 10 = 4560 cycles
  
  Entire refresh
    (Search OAM + Transfer data + H-Blank) * 144 + V-Blank
    456 * 144 + 4560 = 70224

  * `https://gbdev.gg8.se/wiki/articles/Video_Ppu`_
  * `https://nnarain.github.io/2016/09/09/Gameboy-LCD-Controller.html`_
  * `https://www.reddit.com/r/EmuDev/comments/8uahbc/dmg_bgb_lcd_timings_and_cnt/e1iooum/`_

]##
import
  imageman,
  mem, interrupt, util



const
  Width = 160
  Height = 144

  DotFrequency = 4194304

  VramStartAddress = 0x8000
  OamStartAddress = 0xfe00

  MapAddress = [ 0x9800, 0x9C00 ]
  MapSize = 32
  TileAddress = [ 0x8800, 0x8000 ]

type
  PpuGrayShade = enum
    gsWhite = 0
    gsLightGray = 1
    gsDarkGray = 2
    gsBlack = 3
  
  PpuMode = enum
    mHBlank = 0
    mVBlank = 1
    mSearchingOam = 2
    mDataTransfer = 3

  PpuIoState* {.bycopy.} = tuple
    lcdc:     uint8   ## 0xff40  The main LCD control register.
                      ##   bit 7 - LCD Ppu enable flag
                      ##   bit 6 - Window background map selection. (0=0x9800-0x9bff, 1=0x9c00-0x9fff)
                      ##   bit 5 - Window enable flag
                      ##   bit 4 - BG and Window tile addressing mode. (0=0x8800-0x97ff, 1=0x8000-0x8fff)
                      ##   bit 3 - BG map selection, similar to _bit 6_. (0=0x9800-0x9bff, 1=0x9c00-0x9fff)
                      ##   bit 2 - OBJ size. 0: 8x8, 1: 8x16
                      ##   bit 1 - OBJ Ppu enable flag
                      ##   bit 0 - BG/Window Ppu/Priority
                      ##           When Bit 0 is cleared, both background and window become blank (white), and
                      ##           the Window Ppu Bit is ignored in that case. Only Sprites may still be displayed
                      ##           (if enabled in Bit 1).
    stat:     uint8   ## 0xff41  LCDC Status (R/W)
                      ##   bit 6   - LYC=LY Coincidence Interrupt (R/W)
                      ##   bit 5   - Mode 2 OAM Interrupt (R/W)
                      ##   bit 4   - Mode 1 V-Blank Interrupt (R/W)
                      ##   bit 3   - Mode 0 H-Blank Interrupt (R/W)
                      ##   bit 2   - Coincidence Flag (0: LYC != LY, 1: LYC = LY) (R)
                      ##   bit 1-0 - Mode Flag (see _PpuMode_) (R)
                      ##               0: During H-Blank
                      ##               1: During V-Blank
                      ##               2: During Searching OAM
                      ##               3: During Transferring Data to LCD Driver
    scy, scx: uint8
    ly:       uint8   ## 0xff44  Y-Coordinate (R)
                      ##   The LY indicates the vertical line to which the present data is transferred to the LCD Driver.
                      ##   The LY can take on any value between 0 through 153. The values between 144 and 153 indicate
                      ##   the V-Blank period.
    lyc:      uint8   ## 0xff45  LY Compare (R/W)
                      ##   The Gameboy permanently compares the value of the LYC and LY registers. When both values are
                      ##   identical, the coincident bit in the STAT register becomes set, and (if enabled) a STAT interrupt
                      ##   is requested.
    dma:      uint8
    bgp:      uint8   ## 0xff47  BG Palette Data (R/W) [DMG Only]
                      ##   Color number _PpuGrayShades_ translation for BG and Window tiles.
                      ##     bit 7-6 - _PpuGrayShades_ for color number 3
                      ##     bit 5-4 - _PpuGrayShades_ for color number 2
                      ##     bit 3-2 - _PpuGrayShades_ for color number 1
                      ##     bit 1-0 - _PpuGrayShades_ for color number 0
    obp:     array[2, uint8]
                      ## 0xff48  Object Palette Data (R/W) [DMG Only]
                      ##   Color number _PpuGrayShades_ translation sprite palette.
                      ##   Works exactly as _bgp_, except color number 0 is transparent.
    unk2:     array[6, uint8]

  PpuSpriteAttribute {.bycopy.} = tuple
    y, x:  uint8      ## Specifies the sprite position (x - 8, y - 16)
    tile:  uint8      ## Specifies the tile number (0x00..0xff) from the memory at 0x8000-0x8fff
    flags: uint8      ## Attributes
                      ##   bit 7   - OBJ-to-BG Priority (0=OBJ Above BG, 1=OBJ Behind BG color 1-3)
                      ##             (Used for both BG and Window. BG color 0 is always behind OBJ)
                      ##   bit 6   - Y flip (0=Normal, 1=Vertically mirrored)
                      ##   bit 5   - X flip (0=Normal, 1=Horizontally mirrored)
                      ##   bit 4   - Palette number (0=OBP0, 1=OBP1) [DMG Only]
                      ##   bit 3   - Tile VRAM-Bank (0=Bank 0, 1=Bank 1) [CGB Only]
                      ##   bit 2-0 - Palette number (OBP0-7) [CGB Only]
  
  PpuVram = array[8192, uint8]
  
  PpuOam = array[40, PpuSpriteAttribute]

  PpuState* = tuple
    io: PpuIoState
    vram: PpuVram
    oam: PpuOam
    timer: range[0..457]
    stateIR: bool
    dma: uint16

  Ppu* = ref object
    state*: PpuState
    buffer*: array[Height, array[Width, PpuGrayShade]]
    mcu: Mcu


func isEnabled(self: PpuIoState): bool =
  self.lcdc.testBit(7)

func bgMapAddress(self: PpuIoState): MemAddress =
  MapAddress[self.lcdc.testBit(3).int].MemAddress

func bgTileAddress(self: PpuIoState): MemAddress =
  TileAddress[self.lcdc.testBit(4).int].MemAddress

func spriteSize(self: PpuIoState): bool =
  self.lcdc.testBit(2)

func isObjEnabled(self: PpuIoState): bool =
  self.lcdc.testBit(1)

func isBgEnabled(self: PpuIoState): bool =
  self.lcdc.testBit(0)

func bgColorShade(self: PpuIoState, colorNumber: range[0..3]): PpuGrayShade =
  (self.bgp shl (6 - colorNumber*2) shr 6).PpuGrayShade

func shade(gbPalette: uint8, colorNumber: range[0..3]): PpuGrayShade =
  (gbPalette shl (6 - colorNumber*2) shr 6).PpuGrayShade


func mode(self: var PpuIoState): PpuMode =
  (self.stat and 0b00000011).PpuMode

func `mode=`(self: var PpuIoState, mode: PpuMode) =
  self.stat = self.stat and 0b11111100
  self.stat = self.stat or mode.ord.uint8


func palette*(sprite: PpuSpriteAttribute): int =
  getBit(sprite.flags, 4).int

func isXFlipped*(sprite: PpuSpriteAttribute): bool =
  testBit(sprite.flags, 5)

func isYFlipped*(sprite: PpuSpriteAttribute): bool =
  testBit(sprite.flags, 6)

func isVisible(sprite: PpuSpriteAttribute): bool =
  not (sprite.x == 0 or sprite.x >= 168'u8 or sprite.y == 0 or sprite.y >= 168'u8)


func bgTileAddress(state: PpuState, tileNum: uint8): int =
  if state.io.bgTileAddress().int == 0x8000:
    state.io.bgTileAddress().int + tileNum.int*16
  else:
    0x9000 + (cast[int8](tileNum)).int*16

func objTileAddress(state: PpuState, tileNum: uint8): int =
  0x8000 + tileNum.int*16

iterator tileLine(state: PpuState, tileAddress: int, line: int, palette: uint8, start = 0, flipX = false): PpuGrayShade =
  let
    baseAddress = (tileAddress - VramStartAddress) + (line*2)
    b0 = state.vram[baseAddress]
    b1 = state.vram[baseAddress + 1]
    (a, b) = if flipX: (start, 7) else: (7 - start, 0)
  for j in count(a, b):
    let
      c = (b1.getBit(j) shl 1) or b0.getBit(j)
    yield palette.shade(c)

iterator bgLine*(state: PpuState, x, y: int, width: int): tuple[x: int, shade: PpuGrayShade] =
  let
    mapAddress = state.io.bgMapAddress().int - VramStartAddress
    tileY = (y div 8).wrap32
    startY = y mod 8
  var
    tileX = x div 8
    startX = x mod 8
  block main:
    var
      col = 0
    while true:
      let
        tile = tileY*MapSize + tileX
        tileNum = state.vram[mapAddress + tile]
        tileAddress = state.bgTileAddress(tileNum)
      for shade in state.tileLine(tileAddress, startY, state.io.bgp, startX):
        yield (x: col, shade: shade)
        col += 1
        if col == width:
          break main
      tileX = (tileX + 1).wrap32
      startX = 0

iterator objLine*(state: PpuState, x, y: int, width: int): tuple[x: int, shade: PpuGrayShade] =
  for sprite in state.oam:
    if not sprite.isVisible:
      continue

    let
      sx = sprite.x.int - 8
      sy = sprite.y.int - 16
    if not(y in sy ..< sy+(if state.io.spriteSize: 16 else: 8))or sx+8 < x or sx >= x+width:
      continue

    # TODO: handle sprite OBJ-to-BG Priority
    let
      f = max(x, sx)
      t = min(x+width, sx+8)
    var
      line = 7 - (sy - y + 7)
    if sprite.isYFlipped: line = 7 - line
    var i = f
    for shade in state.tileLine(state.objTileAddress(sprite.tile), line, state.io.obp[sprite.palette], f - sx, sprite.isXFlipped):
      yield (x: i, shade: shade)
      i += 1
      if i == t:
        break

proc step*(self: Ppu): bool {.discardable.} =
  self.state.timer += 1
  if self.state.timer > 456:
    self.state.io.ly += 1
    self.state.timer = 0

    if self.state.io.ly == self.state.io.lyc:
      setBit(self.state.io.stat, 2)
    else:
      clearBit(self.state.io.stat, 2)

  case self.state.io.ly
  of 0..(Height-1):
    case self.state.timer
    of 0..79:
      # mSearchingOam
      self.state.io.mode = mSearchingOam
    of 80:
      # mDataTransfer: start
      self.state.io.mode = mDataTransfer
      if self.state.io.isBgEnabled():
        for x, shade in self.state.bgLine(self.state.io.scx.int, self.state.io.scy.int + self.state.io.ly.int, Width):
          self.buffer[self.state.io.ly.int][x] = shade

      if self.state.io.isObjEnabled():
        for x, shade in self.state.objLine(0, self.state.io.ly.int, Width):
          if shade != gsWhite:
            self.buffer[self.state.io.ly.int][x] = shade
    of 81..247:
      # mDataTransfer
      discard
    of 248..455:
      # mHBlank
      self.state.io.mode = mHBlank
    else:
      discard
  of 144:
    # mVBlank: start
    self.state.io.mode = mVBlank
    self.mcu.raiseInterrupt(iVBlank)
  of 154:
    # mVBlank: end
    self.state.io.ly = 0
    result = true
  else:
    discard

  let
    mode = self.state.io.mode
    stat = ((self.state.io.ly == self.state.io.lyc) and testBit(self.state.io.stat, 6)) or
      (mode == mHBlank and testBit(self.state.io.stat, 3)) or
      (mode == mSearchingOam and testBit(self.state.io.stat, 5)) or
      (mode == mVBlank and (testBit(self.state.io.stat, 4) or testBit(self.state.io.stat, 5)))
  if not self.state.stateIR and stat:
    self.mcu.raiseInterrupt(iLcdStat)
  self.state.stateIR = stat

  if (self.state.dma and 0x00ff) <= 0x009f:
    self.mcu[(OamStartAddress.uint16 + (self.state.dma and 0x00ff)).MemAddress] = self.mcu[self.state.dma]
    self.state.dma += 1


proc pushHandler*(mcu: Mcu, self: Ppu) =
  let
    dmaHandler = MemHandler(
      read: proc(address: MemAddress): uint8 = 0,
      write: proc(address: MemAddress, value: uint8) =
        self.state.dma = value.uint16 shl 8
      ,
      area: 0xff46.MemAddress..0xff46.MemAddress
    )
  mcu.pushHandler(0xff40.MemAddress, addr self.state.io)
  mcu.pushHandler(dmaHandler)
  mcu.pushHandler(VramStartAddress, addr self.state.vram)
  mcu.pushHandler(OamStartAddress, addr self.state.oam)

proc newPpu*(mcu: Mcu): Ppu =
  result = Ppu(
    mcu: mcu
  )
  mcu.pushHandler(result)





const
  Colors: array[PpuGrayShade, ColorRGBU] = [
    [224'u8, 248, 208].ColorRGBU,
    [136'u8, 192, 112].ColorRGBU,
    [52'u8, 104, 86].ColorRGBU,
    [8'u8, 24, 32].ColorRGBU,
  ]

proc tile(self: Ppu, tileAddress: int, gbPalette: uint8): Image[ColorRGBU] =
  result = initImage[ColorRGBU](8, 8)
  let
    baseAddress = tileAddress - VramStartAddress
  for i in 0..7:
    let
      b0 = self.state.vram[baseAddress + i*2]
      b1 = self.state.vram[baseAddress + i*2 + 1]
    for j in 0..7:
      var
        c = 0
      if b0.testBit(j):
        c.setBit(0)
      if b1.testBit(j):
        c.setBit(1)
      result[7 - j, i] = Colors[self.state.io.bgColorShade(c)]

proc bgTile*(self: Ppu, tileNum: int): Image[ColorRGBU] =
  let
    tilePos = self.state.bgTileAddress(tileNum.uint8)
  self.tile(tilePos, self.state.io.bgp)

proc renderTiles*(self: Ppu, b: range[0..2]): Image[ColorRGBU] =
  result = initImage[ColorRGBU](8*16, 8*8)
  for y in 0..7:
    for x in 0..15:
      let
        tileImage = self.bgTile(b*128 + (x + y*16))
      result.blit(tileImage, x*8, y*8)

proc renderSprites*(self: Ppu): Image[ColorRGBU] =
  result = initImage[ColorRGBU](Width, Height)
  for sprite in self.state.oam:
    if sprite.x == 0 or sprite.x >= 160'u8 or sprite.y == 0 or sprite.y >= 168'u8:
      continue
    let
      x = sprite.x.int - 8
      y = sprite.y.int - 16
    var
      tileImage = self.bgTile(sprite.tile.int)
    if x < 0 or y < 0 or x + tileImage.width >= result.width or y + tileImage.height >= result.height:
      # TODO: handle this case
      continue
    if sprite.isXFlipped: tileImage = tileImage.flippedHoriz()
    if sprite.isYFlipped: tileImage = tileImage.flippedVert()
    result.blit(tileImage, x, y)



proc renderBackground*(self: Ppu, drawGrid = true): Image[ColorRGBU] =
  let
    w = MapSize*8
    h = MapSize*8
  result = initImage[ColorRGBU](w, h)
  for y in 0..<h:
    for x, shade in bgLine(self.state, 0, y, w):
      result[x, y] = Colors[shade]
  let
    min0 = [ self.state.io.scx.int, self.state.io.scy.int ]
    max0 = [ self.state.io.scx.int + 160, self.state.io.scy.int + 144 ]
  result.drawLine(max(0, min0[0]), max(0, min0[1]), min(255, min0[0]), min(255, max0[1]), [255'u8, 0, 0].ColorRGBU)
  result.drawLine(max(0, min0[0]), max(0, min0[1]), min(255, max0[0]), min(255, min0[1]), [255'u8, 0, 0].ColorRGBU)

  if drawGrid:
    for x in 1..<MapSize:
      result.drawLine(x*8, 0, x*8, result.height - 1, [0'u8, 255, 0].ColorRGBU)
    for y in 1..<MapSize:
      result.drawLine(0, y*8, result.width - 1, y*8, [0'u8, 255, 0].ColorRGBU)

#[
proc renderSprites*(self: Ppu): Image[ColorRGBU] =
  result = initImage[ColorRGBU](Width, Height)
  for y in 0..<Height:
    for x, shade in self.state.objLine(0, y, Width):
      result[x, y] = Colors[shade]
]#

proc renderLcd*(self: Ppu): Image[ColorRGBU] =
  result = initImage[ColorRGBU](Width, Height)
  for y in 0..<Height:
    for x in 0..<Width:
      result[x, y] = Colors[self.buffer[y][x]]
