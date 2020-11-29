import
  std/[strformat, times, monotimes, options],
  opengl, nimgl/imgui, sdl2, sdl2/audio, impl_sdl, impl_opengl,
  imageman,
  style, gb/[gameboy, rewind], gb/dmg/[cpu, mem, ppu, apu], shell/render
import
  mem_editor, file_popup, toggle

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
  editor.draw("Memory editor", provider, setter, 0x10000)


type
  PpuWindow = object
    bgTexture: Texture
    tileMapTextures: array[3, Texture]
    spriteTexture: Texture
    oamTextures: array[40, Texture]

proc draw(self: var PpuWindow, isOpen: var bool, gameboy: Gameboy) =
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

proc destroy(self: PpuWindow) =
  destroy self.bgTexture
  for texture in self.tileMapTextures:
    destroy texture
  destroy self.spriteTexture
  for texture in self.oamTextures:
    destroy texture

proc initPpuWindow(): PpuWindow =
  result = PpuWindow()
  result.bgTexture = initTexture()
  result.tileMapTextures = [initTexture(), initTexture(), initTexture()]
  result.spriteTexture = initTexture()
  for texture in result.oamTextures.mitems:
    texture = initTexture()


func displayBytes(bytes: int): string =
  const
    Divider = 1000
    Units = [ "B", "kB", "MB", "GB", "TB" ]
  var
    current = bytes.float
  for unit in Units:
    if current <= Divider:
      result = &"{current:6.2f}{unit}"
      break
    current = current / Divider

template rawDataTooltip(body: untyped): untyped =
  igTextDisabled("(raw)")
  if igIsItemHovered():
    igBeginTooltip()
    igPushTextWrapPos(igGetFontSize() * 35.0)
    body
    igPopTextWrapPos()
    igEndTooltip()

func apuDebuggerWindow(isOpen: var bool, gameboy: Gameboy) =
  assert gameboy.kind == gkDMG
  if not isOpen:
    return
  #igSetNextWindowPos(ImVec2(x: 483, y: 25), FirstUseEver)
  #igSetNextWindowSize(ImVec2(x: 236, y: 318), FirstUseEver)
  if igBegin("APU", addr isOpen):
    let
      state = gameboy.dmg.apu.state

    if igCollapsingHeader("General"):
      rawDataTooltip:
        igText("channelCtrl    ")
        igSameLine()
        igTextDisabled(&"0b{state.io.channelCtrl:08b}")
        igText("selectionCtrl  ")
        igSameLine()
        igTextDisabled(&"0b{state.io.selectionCtrl:08b}")
        igText("soundCtrl      ")
        igSameLine()
        igTextDisabled(&"0b{state.io.soundCtrl:08b}")

      igPushItemFlag(ImGuiItemFlags.Disabled, true)
      igPushStyleVar(ImGuiStyleVar.Alpha, igGetStyle().alpha * 0.5)
      var
        isOn = state.isOn
      igCheckbox("Enabled", addr isOn)

      var
        isSo1On = state.isSo1On
        so1Volume = state.so1Volume.int32
      igText("SO1")
      igSameLine()
      igCheckbox("##so1_enabled", addr isSo1On)
      igSameLine()
      igSliderInt("Volume##so1_volume", addr so1Volume, 0, 7, flags = ImGuiSliderFlags.NoInput)

      var
        isSo2On = state.isSo2On
        so2Volume = state.so2Volume.int32
      igText("SO2")
      igSameLine()
      igCheckbox("##so2_enabled", addr isSo2On)
      igSameLine()
      igSliderInt("Volume##so2_volume", addr so2Volume, 0, 7, flags = ImGuiSliderFlags.NoInput)

      igPopStyleVar()
      igPopItemFlag()

    if igCollapsingHeader("Channel 1"):
      igText("ch1Sweep       ")
      igSameLine()
      igTextDisabled(&"{state.io.ch1Sweep:#08x}")
      igText("ch1Len         ")
      igSameLine()
      igTextDisabled(&"{state.io.ch1Len:#08x}")
      igText("ch1Envelope    ")
      igSameLine()
      igTextDisabled(&"{state.io.ch1Envelope:#08x}")
      igText("ch1FrequencyL  ")
      igSameLine()
      igTextDisabled(&"{state.io.ch1FrequencyL:#08x}")
      igText("ch1FrequencyH  ")
      igSameLine()
      igTextDisabled(&"{state.io.ch1FrequencyH:#08x}")

    if igCollapsingHeader("Channel 2"):
      igText("ch2Len         ")
      igSameLine()
      igTextDisabled(&"{state.io.ch2Len:#08x}")
      igText("ch2Envelope    ")
      igSameLine()
      igTextDisabled(&"{state.io.ch2Envelope:#08x}")
      igText("ch2FrequencyL  ")
      igSameLine()
      igTextDisabled(&"{state.io.ch2FrequencyL:#08x}")
      igText("ch2FrequencyH  ")
      igSameLine()
      igTextDisabled(&"{state.io.ch2FrequencyH:#08x}")

    if igCollapsingHeader("Channel 3"):
      igText("ch3Ctr         ")
      igSameLine()
      igTextDisabled(&"{state.io.ch3Ctr:#08x}")
      igText("ch3Len         ")
      igSameLine()
      igTextDisabled(&"{state.io.ch3Len:#08x}")
      igText("ch3Lev         ")
      igSameLine()
      igTextDisabled(&"{state.io.ch3Lev:#08x}")
      igText("ch3FrequencyL  ")
      igSameLine()
      igTextDisabled(&"{state.io.ch3FrequencyL:#08x}")
      igText("ch3FrequencyH  ")
      igSameLine()
      igTextDisabled(&"{state.io.ch3FrequencyH:#08x}")
    
    if igCollapsingHeader("Channel 4"):
      igText("ch4Len       ")
      igSameLine()
      igTextDisabled(&"{state.io.ch4Len:#08x}")
      igText("ch4Envelope  ")
      igSameLine()
      igTextDisabled(&"{state.io.ch4Envelope:#08x}")

  igEnd()

proc controlsWindow(isOpen: var bool, history: History, gameboy: var Gameboy, isRunning: var bool, speedBuffer: var seq[float32]) =
  assert gameboy.kind == gkDMG
  if not isOpen:
    return
  igSetNextWindowPos(ImVec2(x: 5, y: 25), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 152, y: 225), FirstUseEver)
  if igBegin("Controls", addr isOpen) and not igIsWindowCollapsed():
    if igBeginTabBar("options"):
      if igBeginTabItem("General"):
        if igButton("Reset"):
          gameboy = newGameboy(readFile(Rom), if BootRom == "": "" else: readFile(BootRom))
          history.clear()
        igSameLine()
        igToggleButton("is_running", isRunning)
        igPushButtonRepeat(true)
        igSameLine()
        if igButtonArrow("##step", ImGuiDir.Right):
          isRunning = false
          discard gameboy.step()
        igSameLine()
        if igButtonArrow("##step_frame", ImGuiDir.Right):
          isRunning = false
          gameboy.stepFrame()
          history.advance(gameboy)
        igPopButtonRepeat()

        igSameLine(igGetWindowWidth() - 100)
        igTextDisabled(&"{displayBytes(history.sizeInBytes())}")

        igPushItemWidth(-1)
        var
          i = history.index.int32
        if igSliderInt("##history", addr i, 0, history.len.int32, "%d"):
          history.restore(gameboy, i.int)
        igPushItemWidth(0)
        igEndTabItem()

      if igBeginTabItem("Speed"):
        igPlotLines("Speed", addr speedBuffer[0], speedBuffer.len.int32,
          overlay_text = &"{speedBuffer[speedBuffer.high]:6.2f}%",
          scale_min = 0, scale_max = 1000,
          graph_size = ImVec2(x: 0, y: 40))
        igEndTabItem()
    igEndTabBar()
  igEnd()


proc main*() =
  sdl2.init(INIT_VIDEO or INIT_AUDIO)
  let
    window = sdl2.createWindow("GameBoy", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 1280, 720, SDL_WINDOW_RESIZABLE or SDL_WINDOW_OPENGL)
    glContext = window.glCreateContext()
  assert glContext != nil
  if glSetSwapInterval(-1) == -1:
    # If adaptive vsync isn't supported try normal vsync
    discard glSetSwapInterval(1)

  var
    spec: AudioSpec
  spec.freq = 44100
  # TODO: will endiannes break this?
  spec.format = AUDIO_F32LSB
  spec.channels = 2
  spec.samples = 1024

  discard openAudio(addr spec, nil)
  pauseAudio(0)

  loadExtensions()

  discard igCreateContext()
  assert igSdl2InitForOpenGL(window, glContext)
  assert igOpenGL3Init()

  styleVGui()

  var
    speedBuffer = newSeq[float32](30)
    gameboy = newGameboy(readFile(Rom), if BootRom == "": "" else: readFile(BootRom))
    history = newHistory()
    isOpen = true
    isRunning = true
    showApu = true
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
    frameskip = 0

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
        else:
          discard
      of DropFile:
        let
          d = cast[DropEventPtr](addr event)
        if d.kind == DropFile:
          gameboy = newGameboy(readFile($d.file), if BootRom == "": "" else: readFile(BootRom))
          isRunning = true
          freeClipboardText(d.file)
      else:
        discard

    var
      frameCount = 0
    if isRunning:
      try:
        frameCount = gameboy.frame(frameskip)
      except:
        echo getCurrentException().msg
        echo getStackTrace(getCurrentException())
        echo "cpu\t", gameboy.dmg.cpu.state
        isRunning = false
      history.advance(gameboy)
    
    let
      dt = (getMonoTime() - start).inNanoseconds.int
      speed = (frameCount*16_666_666 / dt) * 100
    speedBuffer &= ( if isRunning: speed else: 0 )
    speedBuffer.delete(0)
    start = getMonoTime()

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
        igCheckbox("APU", addr showApu)
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
        if igBeginTabItem("General"):
          if igBeginCombo("Frameskip", if frameskip == 0: "Unlimited" else: $(frameskip - 1)):
            for c in 0..10:
              let
                isSelected = c == frameskip
              if igSelectable(if c == 0: "Unlimited" else: $(c - 1), isSelected):
                frameskip = c
              if isSelected:
                igSetItemDefaultFocus()
            igEndCombo()
          igEndTabItem()
        if igBeginTabItem("Rendering"):
          igText("DMG Palette color")
          igColorEdit3("White", painter.palette[gsWhite])
          igColorEdit3("Light Gray", painter.palette[gsLightGray])
          igColorEdit3("Dark Gray", painter.palette[gsDarkGray])
          igColorEdit3("Black", painter.palette[gsBlack])
          igEndTabItem()
        igEndTabBar()
      igEndPopup()

    ppuWindow.draw(showPpu, gameboy)
    editor.draw(gameboy)
    cpuWindow(showCpu, gameboy)
    apuDebuggerWindow(showApu, gameboy)
    controlsWindow(showControls, history, gameboy, isRunning, speedBuffer)
    
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
    
    var
      path: string
    if filePopup.render(path):
      gameboy = newGameboy(readFile(Rom), if BootRom == "": "" else: readFile(BootRom))
      isRunning = true

    showDemoWindow(showDemo)

    igRender()

    glClearColor(0.45, 0.55, 0.60, 1.00)
    glClear(GL_COLOR_BUFFER_BIT)

    igOpenGL3RenderDrawData(igGetDrawData())

    window.glSwapWindow()

  destroy mainTexture
  destroy ppuWindow
  closeAudio()
  igOpenGL3Shutdown()
  igSdl2Shutdown()
  glDeleteContext(glContext)

  destroy window
  sdl2.quit()
