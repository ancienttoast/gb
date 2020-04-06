import
  std/[strformat, times, monotimes],
  nimgl/[glfw, opengl, imgui], nimgl/imgui/[impl_opengl, impl_glfw],
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

proc initTexture(): Texture =
  glGenTextures(1, addr result.texture)
  glBindTexture(GL_TEXTURE_2D, result.texture)

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST.GLint)

proc upload(self: var Texture, image: Image[ColorRGBU]) =
  glBindTexture(GL_TEXTURE_2D, self.texture)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB.GLint, image.width.GLsizei, image.height.GLsizei, 0, GL_RGB, GL_UNSIGNED_BYTE, unsafeAddr image.data[0])

  self.width = image.width
  self.height = image.height

proc destroy(self: Texture) =
  glDeleteTextures(1, unsafeAddr self.texture)


proc keyProc(window: GLFWWindow, key: int32, scancode: int32,
              action: int32, mods: int32): void {.cdecl.} =
  if key == GLFWKey.ESCAPE and action == GLFWPress:
    window.setWindowShouldClose(true)


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

var
  keys: array[JoypadKey, bool]
  newRom = ""

proc main() =
  assert glfwInit()

  glfwWindowHint(GLFWContextVersionMajor, 3)
  glfwWindowHint(GLFWContextVersionMinor, 3)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE) # Used for Mac
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
  glfwWindowHint(GLFWResizable, GLFW_TRUE)

  let
    window = glfwCreateWindow(1280, 720, "GameBoy")
  assert window != nil

  discard window.setKeyCallback(keyProc)
  window.makeContextCurrent()
  glfwSwapInterval(0)

  assert glInit()

  let
    context = igCreateContext()

  assert igGlfwInitForOpenGL(window, true)
  assert igOpenGL3Init()

  styleVGui()

  var
    gameboy = newGameboy(BootRom)
    isRunning = true
    showPpu = true
    showControls = true
    showCpu = true
    showDemo = false
    bgTexture = initTexture()
    mainTexture = initTexture()
    tileMapTextures = [initTexture(), initTexture(), initTexture()]
    spriteTexture = initTexture()
    oamTextures = newSeq[Texture](40)
    gbRunning = true
  for texture in oamTextures.mitems:
    texture = initTexture()

  gameboy.load(Rom)

  discard window.setKeyCallback(
    proc(window: GLFWWindow, key: int32, scancode: int32, action: int32, mods: int32) {.cdecl.} =
      case key
      of GLFWKey.A: keys[kA] = action != GLFWRelease
      of GLFWKey.S: keys[kB] = action != GLFWRelease
      of GLFWKey.Enter: keys[kStart] = action != GLFWRelease
      of GLFWKey.RightShift: keys[kSelect] = action != GLFWRelease
      of GLFWKey.Up: keys[kUp] = action != GLFWRelease
      of GLFWKey.Left: keys[kLeft] = action != GLFWRelease
      of GLFWKey.Down: keys[kDown] = action != GLFWRelease
      of GLFWKey.Right: keys[kRight] = action != GLFWRelease
      else:
        discard
  )

  discard window.setDropCallback(
    proc(window: GLFWWindow, path_count: int32, paths: cstringArray) {.cdecl.} =
      if path_count > 0:
        newRom = $paths[0]
  )

  var
    start = getMonoTime()
  while not window.windowShouldClose:
    glfwPollEvents()

    if newRom != "":
      gameboy = newGameboy(BootRom)
      gameboy.load(newRom)
      newRom = ""
      gbRunning = true
      isRunning = true

    for key, state in keys:
      gameboy.joypad.setKey(key, state)

    let
      dt = (getMonoTime() - start).inNanoseconds.int
      speed = (16_666_666 / dt) * 100
    start = getMonoTime()
    if isRunning:
      try:
        var
          needsRedraw = false
        while not needsRedraw and gbRunning and isRunning:
          let
            cycles = gameboy.cpu.step(gameboy.mcu) * 4
          for i in 0..<cycles:
            gameboy.timer.step()
            needsRedraw = needsRedraw or gameboy.ppu.step()
      except:
        echo getCurrentException().msg
        echo getStackTrace(getCurrentException())
        echo "cpu\t", gameboy.cpu.state
        #echo "display\t", gameboy.display.state
        gbRunning = false

    igOpenGL3NewFrame()
    igGlfwNewFrame()
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
      igSetNextWindowPos(ImVec2(x: 745, y: 24), FirstUseEver)
      igSetNextWindowSize(ImVec2(x: 530, y: 570), FirstUseEver)
      igBegin("Ppu", flags = ImGuiWindowFlags.NoResize or ImGuiWindowFlags.NoCollapse)
      if not igIsWindowCollapsed():
        if igBeginTabBar("display"):
          if igBeginTabItem("BG map"):
            let
              image = gameboy.ppu.renderBackground(drawGrid = false)
            bgTexture.upload(image)
            igImage(cast[pointer](bgTexture.texture), ImVec2(x: bgTexture.width.float32 * 2, y: bgTexture.height.float32 * 2))
            igEndTabItem()
          if igBeginTabItem("Sprite map"):
            let
              image = gameboy.ppu.renderSprites()
            spriteTexture.upload(image)
            igImage(cast[pointer](spriteTexture.texture), ImVec2(x: spriteTexture.width.float32 * 2, y: spriteTexture.height.float32 * 2))
            igEndTabItem()
          if igBeginTabItem("Tile map"):
            for i in 0..2:
              let
                image = gameboy.ppu.renderTiles(i)
              tileMapTextures[i].upload(image)
              igImage(cast[pointer](tileMapTextures[i].texture), ImVec2(x: tileMapTextures[i].width.float32 * 2, y: tileMapTextures[i].height.float32 * 2))
            igEndTabItem()
          if igBeginTabItem("OAM"):
            let
              oams = gameboy.ppu.state.oam
            igColumns(8, "oam", true)
            var
              col = 0
            for i, oam in oams:
              let
                tile = gameboy.ppu.bgTile(oam.tile.int)
              oamTextures[i].upload(tile)
              igImage(cast[pointer](oamTextures[i].texture), ImVec2(x: oamTextures[i].width.float32 * 2, y: oamTextures[i].height.float32 * 2))
              igSameLine()
              igBeginGroup()
              igText(&"{oam.y:#04x}")
              igText(&"{oam.x:#04x}")
              igText(&"{oam.tile:#04x}")
              igText(&"{oam.flags:#04x}")
              igEndGroup()

              igNextColumn()

              col += 1
              if col >= 8 and i < 39:
                col = 0
                igSeparator()
            igEndTabItem()
          igEndTabBar()
      igEnd()
    
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

    window.swapBuffers()

  destroy spriteTexture
  destroy bgTexture
  destroy mainTexture
  igOpenGL3Shutdown()
  igGlfwShutdown()
  context.igDestroyContext()

  window.destroyWindow()
  glfwTerminate()

main()
