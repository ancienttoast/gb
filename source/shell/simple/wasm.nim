import
  sdl2,
  gb/[dmg, cpu, joypad], shell/render



const
  BootRom = ""
  Rom = staticRead("../123/gb-test-roms-master/cpu_instrs/cpu_instrs.gb")




proc hackedRawProc*[T: proc](x: T): pointer {.noSideEffect, inline.} =
  ## Retrieves the raw proc pointer of the closure `x`. This is
  ## useful for interfacing closures with C.
  {.emit: """
  `result` = (void *)`x`.ClP_0;
  """.}

type
  em_arg_callback_func = proc(data: pointer) {.cdecl.}
proc emscripten_set_main_loop_arg*(f: em_arg_callback_func, data: pointer, fps: cint, simulate_infinite_loop: cint) {.importc.}
proc emscripten_cancel_main_loop*() {.importc.}




const
  Scale = 4
  Width = 160
  Height = 144

proc main*() =
  sdl2.init(INIT_VIDEO or INIT_AUDIO)
  let
    window = sdl2.createWindow("GameBoy", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, Width * Scale, Height * Scale, 0)
    renderer = window.createRenderer(-1, 0)
  assert window != nil
  assert renderer != nil

  let
    texture = renderer.createTexture(SDL_PIXELFORMAT_RGB24, SDL_TEXTUREACCESS_STREAMING, Width, Height)
  assert texture != nil

  var
    gameboy = newGameboy(BootRom)
    isRunning = true
    isOpen = true
  gameboy.load(Rom)

  let loop = proc() {.closure.} =
    var
      event: sdl2.Event
    while sdl2.pollEvent(event).bool:
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
      else:
        discard

    if isRunning:
      try:
        var
          needsRedraw = false
        while not needsRedraw and isRunning:
          needsRedraw = needsRedraw or gameboy.step()
      except:
        echo getCurrentException().msg
        echo getStackTrace(getCurrentException())
        echo "cpu\t", gameboy.cpu.state
        isRunning = false

    var
      image = gameboy.ppu.renderLcd()
    let
      r = texture.updateTexture(nil, addr image.data[0], Width * 3).int
    if r != 0:
      echo sdl2.getError()

    renderer.setDrawColor(255, 0, 0, 255)
    renderer.clear()
    renderer.copy(texture, nil, nil)
    renderer.present()
  
  let
    env = protect(loop.rawEnv)
  emscripten_set_main_loop_arg(cast[em_arg_callback_func](loop.hackedRawProc), env.data, -1, 1)
  dispose(env)

  destroy texture
  destroy renderer
  destroy window
  sdl2.quit()
