##[

  Video Display
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

  * `https://gbdev.gg8.se/wiki/articles/Video_Display`_
  * `https://nnarain.github.io/2016/09/09/Gameboy-LCD-Controller.html`_
  * `https://www.reddit.com/r/EmuDev/comments/8uahbc/dmg_bgb_lcd_timings_and_cnt/e1iooum/`_

]##
import
  mem, bitops, imageman



const
  Width = 160
  Height = 144

  DotFrequency = 4194304

  VramStartAddress = 0x8000
  OamStartAddress = 0xfe00

  MapAddress = [ 0x9800, 0x9C00 ]

type
  DisplayGrayShades = enum
    gsWhite = 0
    gsLightGray = 1
    gsDarkGray = 2
    gsBlack = 3
  
  DisplayMode = enum
    mHBlank = 0
    mVBlank = 1
    mSearchingOam = 2
    mDataTransfer = 3

  DisplayIOState* {.bycopy.} = tuple
    lcdc:     uint8   ## 0xff40  The main LCD control register.
                      ##   bit 7 - LCD display enable flag
                      ##   bit 6 - Window background map selection. If 0 0x9800 tilemap is used, otherwise  0x9C00.
                      ##   bit 5 - Window enable flag
                      ##   bit 4 - BG and Window tile addressing mode
                      ##   bit 3 - BG map selection, similar to _bit 6_. If 0 0x9800, otherwise 0x9C00.
                      ##   bit 2 - OBJ size. 0: 8x8, 1: 8x16
                      ##   bit 1 - OBJ display enable flag
                      ##   bit 0 - BG/Window display/Priority
                      ##           When Bit 0 is cleared, both background and window become blank (white), and
                      ##           the Window Display Bit is ignored in that case. Only Sprites may still be displayed
                      ##           (if enabled in Bit 1).
    stat:     uint8   ## 0xff41  LCDC Status (R/W)
                      ##   bit 6   - LYC=LY Coincidence Interrupt (R/W)
                      ##   bit 5   - Mode 2 OAM Interrupt (R/W)
                      ##   bit 4   - Mode 1 V-Blank Interrupt (R/W)
                      ##   bit 3   - Mode 0 H-Blank Interrupt (R/W)
                      ##   bit 2   - Coincidence Flag (0: LYC != LY, 1: LYC = LY) (R)
                      ##   bit 1-0 - Mode Flag (see _DisplayMode_) (R)
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
                      ##   Color number _DisplayGrayShades_ translation for BG and Window tiles.
                      ##     bit 7-6 - _DisplayGrayShades_ for color number 3
                      ##     bit 5-4 - _DisplayGrayShades_ for color number 2
                      ##     bit 3-2 - _DisplayGrayShades_ for color number 1
                      ##     bit 1-0 - _DisplayGrayShades_ for color number 0
    obp0:     uint8   ## 0xff48  Object Palette 0 Data (R/W) [DMG Only]
                      ##   Color number _DisplayGrayShades_ translation sprite palette 0.
                      ##   Works exactly as _bgp_, except color number 0 is transparent.
    obp1:     uint8   ## 0xff48  Object Palette 1 Data (R/W) [DMG Only]
                      ##   Color number _DisplayGrayShades_ translation sprite palette 1.
                      ##   Works exactly as _bgp_, except color number 0 is transparent.
    unk2:     array[6, uint8]

  DisplaySpriteAttribute {.bycopy.} = tuple
    y, x:  uint8      ## Specifies the sprite position (x - 8, y - 16)
    tile:  uint8
    flags: uint8
  
  DisplayVram = array[8192, uint8]
  
  DisplayOam = array[40, DisplaySpriteAttribute]

  DisplayState = tuple
    io: DisplayIOState
    vram: DisplayVram
    oam: DisplayOam
    timer: range[0..457]

  Display* = ref object
    state*: DisplayState
    mcu: Mcu


func isEnabled(self: DisplayIOState): bool =
  self.lcdc.testBit(7)

func bgMapAddress(self: DisplayIOState): MemAddress =
  MapAddress[self.lcdc.testBit(3).int].MemAddress

func spriteSize(self: DisplayIOState): bool =
  self.lcdc.testBit(2)

func bgColorShade(self: DisplayIOState, colorNumber: range[0..3]): DisplayGrayShades =
  (self.bgp shl (6 - colorNumber*2) shr 6).DisplayGrayShades


func step*(self: Display): bool {.discardable.} =
  self.state.timer += 1
  if self.state.timer > 456:
    self.state.io.ly += 1
    self.state.timer = 0
  if self.state.io.ly == 154:
    self.state.io.ly = 0
    result = true
  
  if self.state.io.ly == 144:
    self.mcu.write(0xff0f, self.mcu.read(0xff0f) or 0b00000001)

proc pushHandler*(mcu: Mcu, self: Display) =
  mcu.pushHandler(0xff40.MemAddress, addr self.state.io)
  mcu.pushHandler(VramStartAddress, addr self.state.vram)
  mcu.pushHandler(OamStartAddress, addr self.state.oam)

proc newDisplay*(mcu: Mcu): Display =
  result = Display(
    mcu: mcu
  )
  mcu.pushHandler(result)



const
  Colors: array[DisplayGrayShades, ColorRGBU] = [
    [44'u8, 33, 55].ColorRGBU,
    [118'u8, 68, 98].ColorRGBU,
    [237'u8, 180, 161].ColorRGBU,
    [169'u8, 104, 104].ColorRGBU
  ]

proc tile(self: Display, tileNum: int): Image[ColorRGBU] =
  result = initImage[ColorRGBU](8, 8)
  let
    tilePos = 0x8000 + tileNum*16
  for i in 0..7:
    let
      b0 = self.mcu[(tilePos + i*2).MemAddress]
      b1 = self.mcu[(tilePos + i*2).MemAddress + 1]
    for j in 0..7:
      var
        c = 0
      if b0.testBit(j):
        c.setBit(0)
      if b1.testBit(j):
        c.setBit(1)
      result[7 - j, i] = Colors[self.state.io.bgColorShade(c)]

proc renderTiles*(self: Display, b: range[0..2]): Image[ColorRGBU] =
  result = initImage[ColorRGBU](8*16, 8*8)
  for y in 0..7:
    for x in 0..15:
      let
        tileImage = self.tile(b*128 + (x + y*16))
      result.blit(tileImage, x*8, y*8)

proc renderBackground*(self: Display): Image[ColorRGBU] =
  let
    mapAddress = self.state.io.bgMapAddress()
  result = initImage[ColorRGBU](256, 256)
  for y in 0..<32:
    for x in 0..<32:
      let
        tilePos = (mapAddress.int + y*32 + x).MemAddress
        tileNum = self.mcu[tilePos].int
        tileImage = self.tile(tileNum)
      result.blit(tileImage, x*8, y*8)
  #result.drawLine(self.state.io.scx.int, self.state.io.scy.int, self.state.io.scx.int + 160, self.state.io.scy.int, [255'u8, 0, 0].ColorRGBU)
  #result.drawLine(self.state.io.scx.int, self.state.io.scy.int, self.state.io.scx.int, self.state.io.scy.int + 144, [255'u8, 0, 0].ColorRGBU)

proc renderSprites*(self: Display): Image[ColorRGBU] =
  result = initImage[ColorRGBU](Width, Height)
  for sprite in self.state.oam:
    if sprite.x == 0 or sprite.x >= 160'u8 or sprite.y == 0 or sprite.y >= 168'u8:
      continue
    let
      x = sprite.x - 8
      y = sprite.y - 16
      tileImage = self.tile(sprite.tile.int)
    result.blit(tileImage, x.int, y.int)
