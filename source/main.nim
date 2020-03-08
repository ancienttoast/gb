import
  std/strformat,
  nimgl/[glfw, opengl, imgui], nimgl/imgui/[impl_opengl, impl_glfw],
  imageman,
  style, gb, gb/[mem, cpu, timer, display, cartridge]



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

  assert glInit()

  let
    context = igCreateContext()

  assert igGlfwInitForOpenGL(window, true)
  assert igOpenGL3Init()

  styleVGui()

  var
    gameboy = newGameboy()
    isRunning = true
    showBgMap = true
    showSpriteMap = true
    showControls = true
    showCpu = true
    showDemo = false
    bgTexture = initTexture()
    spriteTexture = initTexture()
    gbRunning = true
    prevState = gameboy.cpu.state
  while not window.windowShouldClose:
    glfwPollEvents()

    if isRunning:
      try:
        var
          needsRedraw = false
        while not needsRedraw and gbRunning:
          prevState = gameboy.cpu.state
          gameboy.cpu.step(gameboy.mcu)
          gameboy.timer.step()
          needsRedraw = gameboy.display.step()
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
        igCheckbox("BG Window", addr showBgMap)
        igCheckbox("Sprite Window", addr showSpriteMap)
        igCheckbox("Cpu window", addr showCpu)
        igSeparator()
        igCheckbox("Demo", addr showDemo)
        igEndMenu()
      igEndMainMenuBar()

    if showBgMap:
      igSetNextWindowSize(ImVec2(x: 530, y: 550), FirstUseEver)
      igBegin("BG map", flags = ImGuiWindowFlags.NoResize or ImGuiWindowFlags.NoCollapse)
      if not igIsWindowCollapsed():
        let
          image = gameboy.display.renderBackground()
        bgTexture.upload(image)
        igImage(cast[pointer](bgTexture.texture), ImVec2(x: bgTexture.width.float32 * 2, y: bgTexture.height.float32 * 2))
      igEnd()
    
    if showSpriteMap:
      igSetNextWindowSize(ImVec2(x: 337, y: 325), FirstUseEver)
      igBegin("Sprite map", flags = ImGuiWindowFlags.NoResize or ImGuiWindowFlags.NoCollapse)
      if not igIsWindowCollapsed():
        let
          image = gameboy.display.renderSprites()
        spriteTexture.upload(image)
        igImage(cast[pointer](spriteTexture.texture), ImVec2(x: spriteTexture.width.float32 * 2, y: spriteTexture.height.float32 * 2))
      igEnd()
    
    if showCpu:
      igBegin("CPU")
      if not igIsWindowCollapsed():
        let
          state = gameboy.cpu.state
        for r in Register16:
          igTextDisabled($r)
          igSameLine()
          igText(&"{state[r]:#06x}")

        igSeparator()
        
        igTextDisabled("SP")
        igSameLine()
        igText(&"{state.sp:#06x}")

        igTextDisabled("PC")
        igSameLine()
        igText(&"{state.pc:#06x}")

        igSeparator()

        igTextDisabled("flags")
        igSameLine()
        igText(&"{state.flags}")

        igSeparator()

        igTextDisabled("ie")
        igSameLine()
        igText(&"{state.ie}")

        igTextDisabled("if")
        igSameLine()
        igText(&"{state.`if`}")

        igTextDisabled("waitForInterrupt")
        igSameLine()
        igText(&"{state.waitForInterrupt}")
      igEnd()

    if showControls:
      igBegin("Controls")

      if igButton("Reset"):
        gameboy = newGameboy()
        gbRunning = true
      
      igSeparator()

      if igButton("Play"):
        isRunning = true

      if igButton("Pause"):
        isRunning = false

      if igButton("Step"):
        isRunning = false
        gameboy.cpu.step(gameboy.mcu)
        gameboy.timer.step()
        discard gameboy.display.step()
      
      igSeparator()

      igCheckbox("gbRunning", addr gbRunning)
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
  igOpenGL3Shutdown()
  igGlfwShutdown()
  context.igDestroyContext()

  window.destroyWindow()
  glfwTerminate()

main()
