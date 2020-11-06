import
  std/[strformat, times, monotimes, options, streams],
  opengl, nimgl/imgui, sdl2, impl_sdl, impl_opengl,
  imageman,
  style, gb/gameboy, gb/dmg/[cpu, mem, ppu], shell/render
import
  mem_editor, file_popup

when defined(profiler):
  import nimprof



const
  BootRom = ""
  Rom = "123/games/gb/Super Mario Land 2 - 6 Golden Coins (USA, Europe) (Rev B).gb"
  #Rom = "123/dmg-acid2.gb"



type
  Texture = tuple[texture: GLuint, width, height: int]

proc upload(self: var Texture, image: Image[ColorRGBU]) =
  glBindTexture(GL_TEXTURE_2D, self.texture)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB.GLint, image.width.GLsizei, image.height.GLsizei, 0, GL_RGB, GL_UNSIGNED_BYTE, unsafeAddr image.data[0])

  self.width = image.width
  self.height = image.height

proc initTexture(): Texture =
  glGenTextures(1, addr result.texture)
  glBindTexture(GL_TEXTURE_2D, result.texture)

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)

proc destroy(self: Texture) =
  glDeleteTextures(1, unsafeAddr self.texture)


proc igTexture(self: Texture, scale: float) =
  igImage(cast[pointer](self.texture), ImVec2(x: self.width.float32 * scale, y: self.height.float32 * scale))

proc igColorEdit3(label: cstring, col: var ColorRGBU, flags: ImGuiColorEditFlags = 0.ImGuiColorEditFlags): bool {.discardable.} =
  var
    floatColor: array[3, float32]
  floatColor[0] = col[0].int / 255
  floatColor[1] = col[1].int / 255
  floatColor[2] = col[2].int / 255
  result = igColorEdit3(label, floatColor, flags)
  if result:
    col[0] = (floatColor[0] * 255).uint8
    col[1] = (floatColor[1] * 255).uint8
    col[2] = (floatColor[2] * 255).uint8


proc showDemoWindow(isOpen: var bool) =
  if not isOpen:
    return
  igShowDemoWindow(addr isOpen)

proc cpuWindow(isOpen: var bool, gameboy: Gameboy) =
  assert gameboy.kind == gkDMG
  if not isOpen:
    return
  let
    state = gameboy.dmg.cpu.state
  igSetNextWindowPos(ImVec2(x: 483, y: 25), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 236, y: 318), FirstUseEver)
  if igBegin("CPU", addr isOpen):
    for r in Register16:
      igTextDisabled($r)
      igSameLine()
      igText(&"{state[r]:#06x}")

      if r == rAF:
        igSameLine()
        igText(&"{state.flags}")

    igSeparator()
    
    igTextDisabled("SP")
    igSameLine()
    igText(&"{state.sp:#06x}")

    igTextDisabled("PC")
    igSameLine()
    igText(&"{state.pc:#06x}")

    igSeparator()

    igTextDisabled("ie")
    igSameLine()
    igText(&"{cast[uint8](state.ie):#04x} {state.ie}")

    igTextDisabled("if")
    igSameLine()
    igText(&"{cast[uint8](state.`if`):#04x} {state.`if`}")

    igSeparator()

    igTextDisabled("status")
    igSameLine()
    igText(&"{state.status}")
  igEnd()

proc draw(editor: MemoryEditor, gameboy: Gameboy) =
  let
    provider = proc(address: int): uint8 = gameboy.dmg.mcu[address.uint16]
    setter = proc(address: int, value: uint8) = gameboy.dmg.mcu[address.uint16] = value
  igSetNextWindowPos(ImVec2(x: 162, y: 348), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 557, y: 300), FirstUseEver)
  editor.draw("Memory editor", provider, setter, 0xffff)


type
  PpuWindow = ref object
    bgTexture: Texture
    tileMapTextures: array[3, Texture]
    spriteTexture: Texture
    oamTextures: array[40, Texture]

proc draw(self: PpuWindow, isOpen: var bool, gameboy: Gameboy) =
  assert gameboy.kind == gkDMG
  if not isOpen:
    return
  let
    ppu = gameboy.dmg.ppu
    painter = initPainter(PaletteDefault)
  igSetNextWindowPos(ImVec2(x: 724, y: 25), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 530, y: 570), FirstUseEver)
  if igBegin("Ppu", addr isOpen, flags = ImGuiWindowFlags.NoResize):
    if igBeginTabBar("display"):
      if igBeginTabItem("BG map"):
        let
          image = painter.renderBackground(ppu, drawGrid = false)
        self.bgTexture.upload(image)
        igTexture(self.bgTexture, 2)
        igEndTabItem()
      if igBeginTabItem("Sprite map"):
        let
          image = painter.renderSprites(ppu)
        self.spriteTexture.upload(image)
        igTexture(self.spriteTexture, 2)
        igEndTabItem()
      if igBeginTabItem("Tile map"):
        for i in 0..2:
          let
            image = painter.renderTiles(ppu, i)
          self.tileMapTextures[i].upload(image)
          igTexture(self.tileMapTextures[i], 2)
        igEndTabItem()
      if igBeginTabItem("OAM"):
        var
          selected = 0
        let
          oams = ppu.state.oam
        for i, oam in oams:
          if igBeginChild("oam" & $i, ImVec2(x: igGetWindowContentRegionWidth() / 9, y: 80), true, ImGuiWindowFlags.NoScrollbar):
            if igIsWindowHovered():
              selected = i
            let
              tile = painter.bgTile(ppu, oam.tile.int)
            self.oamTextures[i].upload(tile)
            igTexture(self.oamTextures[i], 2)
            igSameLine()
            igBeginGroup()
            igText(&"{oam.y:#04x}")
            igText(&"{oam.x:#04x}")
            igText(&"{oam.tile:#04x}")
            igText(&"{oam.flags:#04x}")
            igEndGroup()
          igEndChild()

          if (i + 1) mod 8 != 0:
            igSameLine()
        
        if igBeginChild("highlight", ImVec2(x: 0, y: 0), true, ImGuiWindowFlags.NoScrollbar):
          let
            oam = oams[selected]
          igTexture(self.oamTextures[selected], 9)

          igSameLine()

          igBeginGroup()
          block:
            igTextDisabled("Flags  ")
            igSameLine()
            igText(&"{oam.flags:08b}")

            igTextDisabled("   Flip x    ")
            igSameLine()
            igText($oam.isXFlipped)
            igTextDisabled("   Flip y    ")
            igSameLine()
            igText($oam.isYFlipped)

            igTextDisabled("   Palette   ")
            igSameLine()
            igText($oam.palette)
          igEndGroup()

          igSameLine()

          igBeginGroup()
          block:
            igTextDisabled("Position  ")
            igSameLine()
            igText(&"{oam.x - 8:3}x{oam.y - 16:3}")
            igTextDisabled("Tile      ")
            igSameLine()
            igText(&"{oam.tile:3} ({0x8000 + oam.tile*16:#06x})")
            igTextDisabled("Priority  ")
            igSameLine()
            igText(&"{oam.priority}")
          igEndGroup()
        igEndChild()
        
        igEndTabItem()
      igEndTabBar()
  igEnd()

proc initPpuWindow(): PpuWindow =
  result = PpuWindow()
  result.bgTexture = initTexture()
  result.tileMapTextures = [initTexture(), initTexture(), initTexture()]
  result.spriteTexture = initTexture()
  for texture in result.oamTextures.mitems:
    texture = initTexture()

proc destroy(self: PpuWindow) =
  destroy self.bgTexture
  for texture in self.tileMapTextures:
    destroy texture
  destroy self.spriteTexture
  for texture in self.oamTextures:
    destroy texture



proc main*() =
  sdl2.init(INIT_VIDEO or INIT_AUDIO)
  let
    window = sdl2.createWindow("GameBoy", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 1280, 720, SDL_WINDOW_RESIZABLE or SDL_WINDOW_OPENGL)
    glContext = window.glCreateContext()
  assert glContext != nil
  discard glSetSwapInterval(0)

  loadExtensions()

  discard igCreateContext()
  assert igSdl2InitForOpenGL(window, glContext)
  assert igOpenGL3Init()

  styleVGui()

  var
    speedBuffer = newSeq[float32](30)
    gameboy = newGameboy(if BootRom == "": "" else: readFile(BootRom))
    isOpen = true
    isRunning = true
    showPpu = true
    showControls = true
    showCpu = true
    showDemo = false
    showOptions = false
    ppuWindow = initPpuWindow()
    editor = newMemoryEditor()
    mainTexture = initTexture()
    filePopup = initFilePopup("Open file")
    states: array[10, Option[GameboyState]]
    painter = initPainter(PaletteDefault)

  gameboy.load(readFile(Rom))

  var
    start = getMonoTime()
  while isOpen:
    var
      event: sdl2.Event
    while sdl2.pollEvent(event).bool:
      discard igImplSdl2ProcessEvent(event)
      case event.kind
      of QuitEvent:
        isOpen = false
      of KeyDown, KeyUp:
        let
          m = cast[KeyboardEventPtr](addr event)
        case m.keysym.scancode
        of SDL_SCANCODE_A: gameboy.input(iA, m.state == KeyPressed.uint8)
        of SDL_SCANCODE_S: gameboy.input(iB, m.state == KeyPressed.uint8)
        of SDL_SCANCODE_RETURN: gameboy.input(iStart, m.state == KeyPressed.uint8)
        of SDL_SCANCODE_RSHIFT: gameboy.input(iSelect, m.state == KeyPressed.uint8)
        of SDL_SCANCODE_UP: gameboy.input(iUp, m.state == KeyPressed.uint8)
        of SDL_SCANCODE_LEFT: gameboy.input(iLeft, m.state == KeyPressed.uint8)
        of SDL_SCANCODE_DOWN: gameboy.input(iDown, m.state == KeyPressed.uint8)
        of SDL_SCANCODE_RIGHT: gameboy.input(iRight, m.state == KeyPressed.uint8)
        of SDL_SCANCODE_ESCAPE:
          if m.state == KeyReleased.uint8:
            isOpen = false
        else:
          discard
      of DropFile:
        let
          d = cast[DropEventPtr](addr event)
        if d.kind == DropFile:
          gameboy = newGameboy(if BootRom == "": "" else: readFile(BootRom))
          gameboy.load(readFile($d.file))
          isRunning = true
          freeClipboardText(d.file)
      else:
        discard

    let
      dt = (getMonoTime() - start).inNanoseconds.int
      speed = (16_666_666 / dt) * 100
    speedBuffer &= ( if isRunning: speed else: 0 )
    speedBuffer.delete(0)
    start = getMonoTime()
    if isRunning:
      try:
        gameboy.frame()
      except:
        echo getCurrentException().msg
        echo getStackTrace(getCurrentException())
        echo "cpu\t", gameboy.dmg.cpu.state
        isRunning = false

    igOpenGL3NewFrame()
    igImplSdl2NewFrame(window)
    igNewFrame()

    if igBeginMainMenuBar():
      if igBeginMenu("File"):
        if igMenuItem("Open"):
          filePopup.isVisible = true
        igSeparator()
        if igMenuItem("Options"):
          showOptions = true
        igEndMenu()
      if igBeginMenu("Window"):
        igCheckbox("Controls", addr showControls) 
        igCheckbox("Ppu", addr showPpu)
        igCheckbox("Cpu window", addr showCpu)
        igCheckbox("Memory editor", addr editor.open)
        igSeparator()
        igCheckbox("Demo", addr showDemo)
        igEndMenu()
      if igBeginMenu("Savestate"):
        if igBeginMenu("Save"):
          for i, state in states.mpairs:
            let
              label = $i & (if state.isSome: " - " & $state.get.time else: " -")
            if igMenuItem(label):
              state = some(gameboy.save())
          igEndMenu()
        if igBeginMenu("Load"):
          for i, state in states.mpairs:
            let
              label = $i & (if state.isSome: " - " & $state.get.time else: " -")
            if igMenuItem(label):
              gameboy.load(state.get)
          igEndMenu()
        igEndMenu()
      igEndMainMenuBar()

    let
      center = ImVec2(x: igGetIO().displaySize.x * 0.5, y: igGetIO().displaySize.y * 0.5)
    igSetNextWindowPos(center, ImGuiCond.Appearing, ImVec2(x: 0.5, y: 0.5))
    if showOptions:
      igOpenPopup("Options")
    if igBeginPopupModal("Options", addr showOptions, ImGuiWindowFlags.AlwaysAutoResize):
      if igBeginTabBar("options"):
        if igBeginTabItem("Rendering"):
          igText("DMG Palette color")
          igColorEdit3("White", painter.palette[gsWhite])
          igColorEdit3("Light Gray", painter.palette[gsLightGray])
          igColorEdit3("Dark Gray", painter.palette[gsDarkGray])
          igColorEdit3("Black", painter.palette[gsBlack])
          # TODO
          if igButton("Load"): discard
          igSameLine()
          if igButton("Save"): discard
          igEndTabItem()
        igEndTabBar()
      igEndPopup()

    ppuWindow.draw(showPpu, gameboy)
    editor.draw(gameboy)
    
    igSetNextWindowPos(ImVec2(x: 162, y: 25), FirstUseEver)
    igSetNextWindowSize(ImVec2(x: 316, y: 318), FirstUseEver)
    if igBegin("Main"):
      let
        image = painter.renderLcd(gameboy.dmg.ppu)
      mainTexture.upload(image)
      var
        size: ImVec2
      igGetContentRegionAvailNonUDT(addr size)
      igImage(cast[pointer](mainTexture.texture), size)
    igEnd()

    cpuWindow(showCpu, gameboy)
    
    var
      path: string
    if filePopup.render(path):
      gameboy.load(readFile(path))
      isRunning = true

    if showControls:
      igSetNextWindowPos(ImVec2(x: 5, y: 25), FirstUseEver)
      igSetNextWindowSize(ImVec2(x: 152, y: 225), FirstUseEver)
      if igBegin("Controls"):
        if igButton("Reset"):
          gameboy = newGameboy(if BootRom == "": "" else: readFile(BootRom))
          gameboy.load(readFile(Rom))

        igSeparator()

        if igButton("Play"):
          isRunning = true

        if igButton("Pause"):
          isRunning = false

        if igButton("Step"):
          isRunning = false
          discard gameboy.step()

        igCheckbox("Is running", addr isRunning)

        igSeparator()

        if igButton("Dump memory"):
          let
            s = newFileStream("memdump.txt", fmWrite)
          var
            i = 0
          for address in 0..0xffff:
            if i == 0:
              s.write(&"{address:#06x}\t")
            s.write(&"{gameboy.dmg.mcu[address.MemAddress]:02x}")
            i += 1
            if i == 8:
              s.write("\t")
            else:
              s.write(" ")
            if i == 16:
              s.write("\n")
              i = 0
          s.close()

        igSeparator()
        igPlotLines("Speed", addr speedBuffer[0], speedBuffer.len.int32,
          overlay_text = &"{speedBuffer[speedBuffer.high]:6.2f}%",
          scale_min = 0, scale_max = 1000,
          graph_size = ImVec2(x: 0, y: 40))
      igEnd()

    showDemoWindow(showDemo)

    igRender()

    glClearColor(0.45, 0.55, 0.60, 1.00)
    glClear(GL_COLOR_BUFFER_BIT)

    igOpenGL3RenderDrawData(igGetDrawData())

    window.glSwapWindow()

  destroy mainTexture
  destroy ppuWindow
  igOpenGL3Shutdown()
  igSdl2Shutdown()
  glDeleteContext(glContext)

  destroy window
  sdl2.quit()
