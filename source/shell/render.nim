import
  imageman,
  gb/[ppu, util]



type
  Palette = array[PpuGrayShade, ColorRGBU]

  DmgPainter = object
    palette: Palette

proc initPainter*(palette: Palette): DmgPainter =
  DmgPainter(
    palette: palette
  )

proc tile(self: DmgPainter, ppu: Ppu, tileAddress: int, gbPalette: uint8): Image[ColorRGBU] =
  result = initImage[ColorRGBU](8, 8)
  let
    baseAddress = tileAddress - VramStartAddress
  for i in 0..7:
    let
      b0 = ppu.state.vram[baseAddress + i*2]
      b1 = ppu.state.vram[baseAddress + i*2 + 1]
    for j in 0..7:
      var
        c = 0
      if b0.testBit(j):
        c.setBit(0)
      if b1.testBit(j):
        c.setBit(1)
      result[7 - j, i] = self.palette[ppu.state.io.bgColorShade(c)]

proc bgTile*(self: DmgPainter, ppu: Ppu, tileNum: int): Image[ColorRGBU] =
  let
    tilePos = ppu.state.tileAddress(tileNum.uint8)
  self.tile(ppu, tilePos, ppu.state.io.bgp)

proc renderTiles*(self: DmgPainter, ppu: Ppu, b: range[0..2]): Image[ColorRGBU] =
  result = initImage[ColorRGBU](8*16, 8*8)
  for y in 0..7:
    for x in 0..15:
      let
        tileImage = self.bgTile(ppu, b*128 + (x + y*16))
      result.blit(tileImage, x*8, y*8)

proc renderBackground*(self: DmgPainter, ppu: Ppu, drawGrid = true): Image[ColorRGBU] =
  let
    w = MapSize*8
    h = MapSize*8
  result = initImage[ColorRGBU](w, h)
  for y in 0..<h:
    for x, shade in mapLine(ppu.state, 0, y, w, ppu.state.io.bgMapAddress().int - VramStartAddress):
      result[x, y] = self.palette[shade]
  let
    min0 = [ ppu.state.io.scx.int, ppu.state.io.scy.int ]
    max0 = [ ppu.state.io.scx.int + 160, ppu.state.io.scy.int + 144 ]
  result.drawLine(max(0, min0[0]), max(0, min0[1]), min(255, min0[0]), min(255, max0[1]), [255'u8, 0, 0].ColorRGBU)
  result.drawLine(max(0, min0[0]), max(0, min0[1]), min(255, max0[0]), min(255, min0[1]), [255'u8, 0, 0].ColorRGBU)

  if drawGrid:
    for x in 1..<MapSize:
      result.drawLine(x*8, 0, x*8, result.height - 1, [0'u8, 255, 0].ColorRGBU)
    for y in 1..<MapSize:
      result.drawLine(0, y*8, result.width - 1, y*8, [0'u8, 255, 0].ColorRGBU)

proc renderSprites*(self: DmgPainter, ppu: Ppu): Image[ColorRGBU] =
  result = initImage[ColorRGBU](Width, Height)
  for y in 0..<Height:
    for x, shade, priority in ppu.state.objLine(0, y, Width):
      result[x, y] = self.palette[shade]

proc renderLcd*(self: DmgPainter, ppu: Ppu): Image[ColorRGBU] =
  result = initImage[ColorRGBU](Width, Height)
  for y in 0..<Height:
    for x in 0..<Width:
      result[x, y] = self.palette[ppu.buffer[y][x]]


const
  PaletteDefault*: Palette = [
    [224'u8, 248, 208].ColorRGBU,
    [136'u8, 192, 112].ColorRGBU,
    [52'u8, 104, 86].ColorRGBU,
    [8'u8, 24, 32].ColorRGBU,
  ]

  PaletteBlackAndWhite*: Palette = [
    [0xFF'u8, 0xFF, 0xFF].ColorRGBU,
    [0xAA'u8, 0xAA, 0xAA].ColorRGBU,
    [0x55'u8, 0x55, 0x55].ColorRGBU,
    [0x00'u8, 0x00, 0x00].ColorRGBU,
  ]
