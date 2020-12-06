import
  sdl2,
  shell/emscripten,
  gb/gameboy



const
  Scale = 4
  Width = 160
  Height = 144

proc main*() =
  sdl2.init(INIT_VIDEO or INIT_AUDIO)
  let
    window = sdl2.createWindow("GameBoy", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, Width * Scale, Height * Scale, 0)
    renderer = window.createRenderer(-1, Renderer_PresentVsync)
  assert window != nil
  assert renderer != nil

  let
    texture = renderer.createTexture(SDL_PIXELFORMAT_RGB24, SDL_TEXTUREACCESS_STREAMING, Width, Height)
  assert texture != nil

  var
    gameboy = init()
    isRunning = true
  let loop = proc() {.closure.} =
    var
      event: sdl2.Event
    while sdl2.pollEvent(event).bool:
      case event.kind
      of QuitEvent:
        isRunning = false
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
      else:
        discard

    let
      image = gameboy.frame(isRunning)
      r = texture.updateTexture(nil, unsafeAddr image.data[0], Width * 3).int
    if r != 0:
      echo sdl2.getError()

    renderer.setDrawColor(255, 0, 0, 255)
    renderer.clear()
    renderer.copy(texture, nil, nil)
    renderer.present()
  
  emscripten_set_main_loop_arg(loop, -1, 1)

  destroy texture
  destroy renderer
  destroy window
  sdl2.quit()
