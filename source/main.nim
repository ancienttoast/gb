import
  std/[strformat, times, monotimes],
  nimgl/[opengl, imgui], sdl2, impl_sdl, nimgl/imgui/impl_opengl,
  imageman,
  style, gb, gb/[cpu, timer, ppu, joypad]

when defined(profiler):
  import nimprof



const
  #BootRom = "123/[BIOS] Nintendo Game Boy Boot ROM (World).gb"
  BootRom = ""
  #Rom = "123/gb-test-roms-master/cpu_instrs/individual/02-interrupts.gb"
  Rom = "123/Zelda no Densetsu - Yume o Miru Shima (Japan) (Rev A).gb"



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

template `or`(a, b: ImGuiWindowFlags): ImGuiWindowFlags =
  (a.int or b.int).ImGuiWindowFlags


proc cpuWindow(state: CpuState) =
  igSetNextWindowPos(ImVec2(x: 4, y: 185), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 151, y: 196), FirstUseEver)
  igBegin("CPU")
  if not igIsWindowCollapsed():
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
    igText(&"{state.ie}")

    igTextDisabled("if")
    igSameLine()
    igText(&"{state.`if`}")

    igSeparator()

    igTextDisabled("status")
    igSameLine()
    igText(&"{state.status}")
  igEnd()


type
  PpuWindow = ref object
    bgTexture: Texture
    tileMapTextures: array[3, Texture]
    spriteTexture: Texture
    oamTextures: array[40, Texture]

proc draw(self: PpuWindow, ppu: Ppu) =
  igSetNextWindowPos(ImVec2(x: 745, y: 24), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 530, y: 570), FirstUseEver)
  igBegin("Ppu", flags = ImGuiWindowFlags.NoResize or ImGuiWindowFlags.NoCollapse)
  if not igIsWindowCollapsed():
    if igBeginTabBar("display"):
      if igBeginTabItem("BG map"):
        let
          image = ppu.renderBackground(drawGrid = false)
        self.bgTexture.upload(image)
        igTexture(self.bgTexture, 2)
        igEndTabItem()
      if igBeginTabItem("Sprite map"):
        let
          image = ppu.renderSprites()
        self.spriteTexture.upload(image)
        igTexture(self.spriteTexture, 2)
        igEndTabItem()
      if igBeginTabItem("Tile map"):
        for i in 0..2:
          let
            image = ppu.renderTiles(i)
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
              tile = ppu.bgTile(oam.tile.int)
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



proc main() =
  sdl2.init(INIT_VIDEO or INIT_AUDIO)
  let
    window = sdl2.createWindow("GameBoy", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 1280, 720, SDL_WINDOW_RESIZABLE or SDL_WINDOW_OPENGL)
    glContext = window.glCreateContext()
  assert glContext != nil
  discard glSetSwapInterval(0)

  assert glInit()

  let
    context = igCreateContext()
  assert igSdl2InitForOpenGL(window, glContext)
  assert igOpenGL3Init()

  styleVGui()

  var
    gameboy = newGameboy(BootRom)
    isOpen = true
    isRunning = true
    showPpu = true
    showControls = true
    showCpu = true
    showDemo = false
    ppuWindow = initPpuWindow()
    mainTexture = initTexture()
    gbRunning = true

  gameboy.load(Rom)

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
        of SDL_SCANCODE_A: gameboy.joypad[kA] = m.state == KeyPressed.uint8
        of SDL_SCANCODE_S: gameboy.joypad[kB] = m.state == KeyPressed.uint8
        of SDL_SCANCODE_RETURN: gameboy.joypad[kStart] = m.state == KeyPressed.uint8
        of SDL_SCANCODE_RSHIFT: gameboy.joypad[kSelect] = m.state == KeyPressed.uint8
        of SDL_SCANCODE_UP: gameboy.joypad[kUp] = m.state == KeyPressed.uint8
        of SDL_SCANCODE_LEFT: gameboy.joypad[kLeft] = m.state == KeyPressed.uint8
        of SDL_SCANCODE_DOWN: gameboy.joypad[kDown] = m.state == KeyPressed.uint8
        of SDL_SCANCODE_RIGHT: gameboy.joypad[kRight] = m.state == KeyPressed.uint8
        of SDL_SCANCODE_ESCAPE:
          if m.state == KeyReleased.uint8:
            isOpen = false
        else:
          discard
      of DropFile:
        let
          d = cast[DropEventPtr](addr event)
        if d.kind == DropFile:
          gameboy = newGameboy(BootRom)
          gameboy.load($d.file)
          gbRunning = true
          isRunning = true
          freeClipboardText(d.file)
      else:
        discard

    let
      dt = (getMonoTime() - start).inNanoseconds.int
      speed = (16_666_666 / dt) * 100
    start = getMonoTime()
    if isRunning:
      try:
        var
          needsRedraw = false
        while not needsRedraw and gbRunning and isRunning:
          needsRedraw = needsRedraw or gameboy.step()
      except:
        echo getCurrentException().msg
        echo getStackTrace(getCurrentException())
        echo "cpu\t", gameboy.cpu.state
        #echo "display\t", gameboy.display.state
        gbRunning = false

    igOpenGL3NewFrame()
    igImplSdl2NewFrame(window)
    igNewFrame()

    if igBeginMainMenuBar():
      if igBeginMenu("Window"):
        igCheckbox("Controls", addr showControls) 
        igCheckbox("Ppu", addr showPpu)
        igCheckbox("Cpu window", addr showCpu)
        igSeparator()
        igCheckbox("Demo", addr showDemo)
        igEndMenu()
      igEndMainMenuBar()

    if showPpu:
      ppuWindow.draw(gameboy.ppu)
    
    igSetNextWindowPos(ImVec2(x: 402, y: 24), FirstUseEver)
    igSetNextWindowSize(ImVec2(x: 338, y: 326), FirstUseEver)
    igBegin(&"Main", flags = ImGuiWindowFlags.NoResize or ImGuiWindowFlags.NoCollapse)
    if not igIsWindowCollapsed():
      let
        image = gameboy.ppu.renderLcd()
      mainTexture.upload(image)
      igImage(cast[pointer](mainTexture.texture), ImVec2(x: mainTexture.width.float32 * 2, y: mainTexture.height.float32 * 2))
    igEnd()
    
    if showCpu:
      cpuWindow(gameboy.cpu.state)

    if showControls:
      igSetNextWindowPos(ImVec2(x: 4, y: 24), FirstUseEver)
      igSetNextWindowSize(ImVec2(x: 151, y: 156), FirstUseEver)
      igBegin("Controls")

      if igButton("Reset"):
        gameboy = newGameboy(BootRom)
        gameboy.load(Rom)
        gbRunning = true
      
      igSeparator()

      if igButton("Play"):
        isRunning = true

      if igButton("Pause"):
        isRunning = false

      if igButton("Step"):
        isRunning = false
        let
          cycles = gameboy.cpu.step(gameboy.mcu)
        for i in 0..<cycles:
          gameboy.timer.step()
          discard gameboy.ppu.step()
      
      igSeparator()

      igCheckbox("gbRunning", addr gbRunning)
      igText(&"{speed:6.2f}")
      igEnd()
    
    if showDemo:
      igShowDemoWindow(addr showDemo)

    igRender()

    glClearColor(0.45f, 0.55f, 0.60f, 1.00f)
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

main()
