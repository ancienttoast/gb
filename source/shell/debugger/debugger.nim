import
  std/[strformat, times, monotimes, options, streams],
  opengl, nimgl/imgui, sdl2,
  imageman, bingo,
  style, gb/[gameboy, rewind], gb/dmg/[cpu, mem, ppu, apu], shell/render
import
  impl_sdl, impl_opengl,
  widget/[mem_editor, file_popup, toggle, key_popup, misc]

when defined(profiler):
  import nimprof

when defined(emscripten):
  import shell/emscripten



const
  BootRom = ""
  Rom = readFile("123/games/gb/Super Mario Land 2 - 6 Golden Coins (USA, Europe) (Rev B).gb")
  #Rom = readFile("tests/rom/blargg/cpu_instrs/cpu_instrs.gb")



proc igColorEdit3*(label: cstring, col: var ColorRGBU, flags: ImGuiColorEditFlags = 0.ImGuiColorEditFlags): bool {.discardable.} =
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


proc cpuDebuggerWindow(isOpen: var bool, gameboy: Gameboy) =
  if not isOpen or gameboy.kind != gkDMG:
    return
  let
    state = gameboy.dmg.cpu.state
  igSetNextWindowPos(ImVec2(x: 5, y: 497), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 181, y: 218), FirstUseEver)
  if igBegin("CPU", addr isOpen) and not igIsWindowCollapsed():
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


proc memDebuggerWindow(isOpen: var bool, editor: var MemoryEditor, gameboy: Gameboy) =
  let
    provider = proc(address: int): uint8 = gameboy.dmg.mcu[address.uint16]
    setter = proc(address: int, value: uint8) = gameboy.dmg.mcu[address.uint16] = value
  igSetNextWindowPos(ImVec2(x: 191, y: 497), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 552, y: 218), FirstUseEver)
  draw(isOpen, editor, "Memory editor", provider, setter, 0x10000)


type
  PpuWindow = object
    selectedOam: int
    bgTexture: Texture
    tileMapTextures: array[3, Texture]
    spriteTexture: Texture
    oamTextures: array[40, Texture]

proc ppuDebuggerWindow(isOpen: var bool, self: var PpuWindow, gameboy: Gameboy) =
  if not isOpen or gameboy.kind != gkDMG:
    return
  let
    ppu = gameboy.dmg.ppu
    painter = initPainter(PaletteDefault)
  igSetNextWindowPos(ImVec2(x: 748, y: 25), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 527, y: 690), FirstUseEver)
  if igBegin("PPU", addr isOpen) and not igIsWindowCollapsed():
    if igBeginTabBar("display"):
      if igBeginTabItem("BG map"):
        var
          cursor: ImVec2
        igGetCursorScreenPosNonUDT(addr cursor)
        let
          image = painter.renderBackground(ppu)
        self.bgTexture.upload(image)
        igTexture(self.bgTexture, 2)

        let
          color = igGetColorU32(igGetStyle().colors[ImGuiCol.TextDisabled.int32])
          dl = igGetWindowDrawList()
        for x in 1..<MapSize:
          dl.addLine(ImVec2(x: cursor.x + x.float32*TileSize*2, y: cursor.y), ImVec2(x: cursor.x + x.float32*TileSize*2, y: cursor.y + image.h.float32*2), color)
        for y in 1..<MapSize:
          dl.addLine(ImVec2(x: cursor.x, y: cursor.y + y.float32*TileSize*2), ImVec2(x: cursor.x + image.w.float32*2, y: cursor.y + y.float32*TileSize*2), color)

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
        let
          oams = ppu.state.oam
        if igBeginChild("##oam_highlight", ImVec2(x: 0, y: 90), true, ImGuiWindowFlags.NoScrollbar):
          let
            oam = oams[self.selectedOam]
          igTexture(self.oamTextures[self.selectedOam], 9)

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

        if igBeginChild("##oam_main", ImVec2(x: 0, y: 0), true):
          const
            ColumnSize = 55
          let
            columns = max(1, (igGetWindowContentRegionWidth() / ColumnSize).int - 1)
          igColumns(columns.int32, "##oam", false)
          for i, oam in oams:
            let
              tile = painter.bgTile(ppu, oam.tile.int)
            self.oamTextures[i].upload(tile)

            var
              cursor: ImVec2
            igGetCursorPosNonUDT(addr cursor)
            if igSelectable("##oam_" & $i, self.selectedOam == i, size = ImVec2(x: ColumnSize, y: 68)):
              self.selectedOam = i
            igSetCursorPos(cursor)

            igBeginGroup()
            igSpacing()
            igTexture(self.oamTextures[i], 2)
            igSameLine()
            igBeginGroup()
            igText(&"{oam.y:#04x}")
            igText(&"{oam.x:#04x}")
            igText(&"{oam.tile:#04x}")
            igText(&"{oam.flags:#04x}")
            igEndGroup()
            igSpacing()
            igEndGroup()

            igNextColumn()
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


func apuDebuggerWindow(isOpen: var bool, gameboy: Gameboy) =
  if not isOpen or gameboy.kind == gkDMG:
    return
  igSetNextWindowPos(ImVec2(x: 748, y: 50), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 527, y: 364), FirstUseEver)
  igSetNextWindowCollapsed(true, FirstUseEver)
  if igBegin("APU", addr isOpen) and not igIsWindowCollapsed():
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

proc controlsWindow(isOpen: var bool, frameskip: var int, history: History, gameboy: var Gameboy, isRunning: var bool, speedBuffer: var seq[float32]) =
  assert gameboy.kind == gkDMG
  if not isOpen:
    return
  igSetNextWindowPos(ImVec2(x: 5, y: 392), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 237, y: 100), FirstUseEver)
  if igBegin("Controls", addr isOpen) and not igIsWindowCollapsed():
    if igButton("Reset"):
      gameboy.reset()
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

    igSameLine(igGetWindowWidth() - 80)
    igTextDisabled(&"{displayBytes(history.sizeInBytes())}")

    igPushItemWidth(-1)
    var
      i = history.index.int32
    if igSliderInt("##history", addr i, 0, history.high.int32, "%d"):
      isRunning = false
      history.restore(gameboy, i.int)
    igPushItemWidth(0)

    igDummy(ImVec2(x: 0.0, y: igGetFrameHeightWithSpacing() / 2))

    igPlotLines("Speed", addr speedBuffer[0], speedBuffer.len.int32,
      overlay_text = &"{speedBuffer[speedBuffer.high]:6.2f}%",
      scale_min = 0, scale_max = 1000,
      graph_size = ImVec2(x: 0, y: 40))
    
    if igBeginCombo("Frameskip", if frameskip == 0: "Unlimited" else: $(frameskip - 1)):
      for c in 0..10:
        let
          isSelected = c == frameskip
        if igSelectable(if c == 0: "Unlimited" else: $(c - 1), isSelected):
          frameskip = c
        if isSelected:
          igSetItemDefaultFocus()
      igEndCombo()

  igEnd()

proc mainWindow(mainTexture: var Texture, painter: DmgPainter, inputMap: array[InputKey, sdl2.Scancode], device: Gameboy) =
  igSetNextWindowPos(ImVec2(x: 247, y: 25), FirstUseEver)
  igSetNextWindowSize(ImVec2(x: 496, y: 467), FirstUseEver)
  if igBegin("Main"):
    if igIsWindowFocused():
      let
        io = igGetIO()
      for input, scancode in inputMap:
        device.input(input, io.keysDown[scancode.int])
    let
      image = painter.renderLcd(device.dmg.ppu)
    mainTexture.upload(image)
    var
      size: ImVec2
    igGetContentRegionAvailNonUDT(addr size)
    igImage(cast[pointer](mainTexture.texture), size)
  igEnd()


var
  device = newGameboy(Rom, BootRom)
  history = newHistory()

proc loadRom(buffer: UncheckedArray[uint8], size: cint) {.exportc.} =
  var
    data = newString(size)
  for i in 0..<size:
    data[i] = buffer[i].char
  device = newGameboy(data, BootRom)
  history.clear()

proc main*() =
  sdl2.init(INIT_VIDEO or INIT_AUDIO)
  discard sdl2.glSetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES)
  discard sdl2.glSetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2)
  discard sdl2.glSetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0)
  let
    window = sdl2.createWindow("GameBoy", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 1280, 720, SDL_WINDOW_RESIZABLE or SDL_WINDOW_OPENGL)
    glContext = window.glCreateContext()
  assert glContext != nil
  if glSetSwapInterval(-1) == -1:
    # If adaptive vsync isn't supported try normal vsync
    discard glSetSwapInterval(1)

  when not defined(emscripten):
    loadExtensions()

  discard igCreateContext()
  assert igSdl2InitForOpenGL(window, glContext)
  assert igOpenGL3Init()

  styleVGui()

  var
    speedBuffer = newSeq[float32](30)
    isOpen = true
    isRunning = true
    showApu = false
    showPpu = true
    showControls = true
    showCpu = true
    showMem = true
    showDemo = false
    showOptions = false
    ppuWindow = initPpuWindow()
    editor = initMemoryEditor()
    mainTexture = initTexture()
    filePopup = initFilePopup("Open file")
    states: array[10, Option[string]]
    painter = initPainter(PaletteDefault)
    frameskip = 1
    inputMap: array[InputKey, sdl2.Scancode] = [
      SDL_SCANCODE_RIGHT,
      SDL_SCANCODE_LEFT,
      SDL_SCANCODE_UP,
      SDL_SCANCODE_DOWN,
      SDL_SCANCODE_A,
      SDL_SCANCODE_S,
      SDL_SCANCODE_RSHIFT,
      SDL_SCANCODE_RETURN
    ]

  var
    start = getMonoTime()
  let loop = proc() {.closure.} =
    var
      event: sdl2.Event
    while sdl2.pollEvent(event).bool:
      discard igImplSdl2ProcessEvent(event)
      case event.kind
      of QuitEvent:
        isOpen = false
      of DropFile:
        let
          d = cast[DropEventPtr](addr event)
        if d.kind == DropFile:
          device = newGameboy(readFile($d.file), BootRom)
          history.clear()
          isRunning = true
          freeClipboardText(d.file)
      else:
        discard

    var
      frameCount = 0
    if isRunning:
      try:
        frameCount = device.frame(frameskip)
      except:
        echo getCurrentException().msg
        echo getStackTrace(getCurrentException())
        echo "cpu\t", device.dmg.cpu.state
        isRunning = false
      history.advance(device)
    
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
        igSeparator()
        if igMenuItem("Quit"):
          isOpen = false
        igEndMenu()
      if igBeginMenu("Window"):
        igCheckbox("Controls", addr showControls)
        igCheckbox("PPU", addr showPpu)
        igCheckbox("APU", addr showApu)
        igCheckbox("CPU", addr showCpu)
        igCheckbox("Memory editor", addr showMem)
        igSeparator()
        igCheckbox("Demo", addr showDemo)
        igEndMenu()
      if igBeginMenu("Savestate"):
        if igBeginMenu("Save"):
          for i, state in states.mpairs:
            let
              label = $i & (if state.isSome: " - " else: "")# & $state.get.time else: " -")
            if igMenuItem(label):
              let
                save = device.save()
                s = newStringStream()
              s.storeBin(save)
              s.setPosition(0)
              state = some(s.readAll())
          igEndMenu()
        if igBeginMenu("Load"):
          for i, state in states.mpairs:
            let
              label = $i & (if state.isSome: " - " else: "")# & $state.get.time else: " -")
            if igMenuItem(label):
              let
                s = newStringStream(state.get)
              device.load(s.binTo(GameboyState))
          igEndMenu()
        igEndMenu()
      igEndMainMenuBar()

    let
      center = ImVec2(x: igGetIO().displaySize.x * 0.5, y: igGetIO().displaySize.y * 0.5)
    igSetNextWindowPos(center, ImGuiCond.Appearing, ImVec2(x: 0.5, y: 0.5))
    igSetNextWindowSize(ImVec2(x: 377, y: 219), FirstUseEver)
    if showOptions:
      igOpenPopup("Options")
    if igBeginPopupModal("Options", addr showOptions):
      if igBeginTabBar("options"):
        if igBeginTabItem("Rendering"):
          igText("DMG Palette color")
          igColorEdit3("White", painter.palette[gsWhite])
          igColorEdit3("Light Gray", painter.palette[gsLightGray])
          igColorEdit3("Dark Gray", painter.palette[gsDarkGray])
          igColorEdit3("Black", painter.palette[gsBlack])
          igEndTabItem()
        
        if igBeginTabItem("Controls"):
          igSetNextItemOpen(true, ImGuiCond.FirstUseEver)
          if igTreeNode("DMG"):
            for input in InputKey:
              igText($input)
              igSameLine(100)
              let
                key = sdl2.getKeyFromScancode(inputMap[input])
              if igSmallButton($sdl2.getKeyName(key) & "##" & $input):
                openKeyPopup($input)
              let
                (scancode, isInput) = keyPopup($input)
              if isInput:
                inputMap[input] = scancode.Scancode
            igTreePop()
          igEndTabItem()

        igEndTabBar()
      igEndPopup()

    apuDebuggerWindow(showApu, device)
    ppuDebuggerWindow(showPpu, ppuWindow, device)
    memDebuggerWindow(showMem, editor, device)
    cpuDebuggerWindow(showCpu, device)
    controlsWindow(showControls, frameskip, history, device, isRunning, speedBuffer)
    mainWindow(mainTexture, painter, inputMap, device)
    
    var
      path: string
    if filePopup.render(path):
      device = newGameboy(Rom, BootRom)
      history.clear()
      isRunning = true

    showDemoWindow(showDemo)

    igRender()

    glClearColor(0.45, 0.55, 0.60, 1.00)
    glClear(GL_COLOR_BUFFER_BIT)

    igOpenGL3RenderDrawData(igGetDrawData())

    window.glSwapWindow()

  when defined(emscripten):
    emscripten_set_main_loop_arg(loop, -1, 1)
  else:
    while isOpen:
      loop()

  destroy mainTexture
  destroy ppuWindow
  igOpenGL3Shutdown()
  igSdl2Shutdown()
  glDeleteContext(glContext)

  destroy window
  sdl2.quit()
