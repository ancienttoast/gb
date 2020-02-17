##[

  Video Display
  ===========================

  Memory map
  ----------

  0xff40  LCDC LCD Control Register
  0xff47-0xff49  Monochrome palettes - Non CGB mode only
    0xff47  BGP  - BG Palette (R/W)
    0xff48  OBP0 - Object Palette 0 (R/W)
    0xff49  OBP1 - Object Palette 1 (R/W)

  * `https://gbdev.gg8.se/wiki/articles/Video_Display`_
  * `https://nnarain.github.io/2016/09/09/Gameboy-LCD-Controller.html`_

]##
import
  mem



const
  Frequency = 4194304

type
  DisplayState* {.bycopy.} = tuple
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
    stat:     uint8
    scy, scx: uint8
    ly:       uint8   ## 0xff44  Y-Coordinate (R)
                      ##   The LY indicates the vertical line to which the present data is transferred to the LCD Driver.
                      ##   The LY can take on any value between 0 through 153. The values between 144 and 153 indicate
                      ##   the V-Blank period.
    lyc:      uint8
    unk1:     uint8
    bgp:      uint8
    obp0:     uint8
    obp1:     uint8
    unk2:     array[6, uint8]

  Display* = ref object
    state*: DisplayState
    mcu: Mcu


proc register*(self: Display, mcu: Mcu) =
  mcu.pushHandler(0xff40.MemAddress, addr self.state)

proc newDisplay*(): Display =
  result = Display()
  result.state.ly = 144 # TODO: only so the bootrom runs, always VBlank

proc newDisplay*(mcu: Mcu): Display =
  result = newDisplay()
  result.register(mcu)
