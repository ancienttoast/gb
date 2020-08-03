import
  pspsdk/[pspmoduleinfo, pspkerneltypes, psptypes, psploadexec, pspthreadman, pspdisplay],
  pspsdk/[pspgu, pspgum, pspctrl],
  imageman,
  gb/[dmg, joypad]



PSP_MODULE_INFO("GB", 0, 1, 1)
#PSP_MAIN_THREAD_ATTR(THREAD_ATTR_USER)


var
  list {.align(16).}: array[262144, cuint]

var
  texure {.align(16).}: array[256*256, array[4, uint8]]

type
  Vertex = object
    u, v: cfloat
    x, y, z: cfloat

const
  u = 160 / 256
  v = 144 / 256
var
  vertices {.align(16).}: array[2*3, Vertex] = [
    Vertex(u: 0, v: 0, x: 0, y: 0, z: 0),
    Vertex(u: u, v: 0, x: 1, y: 0, z: 0),
    Vertex(u: 0, v: v, x: 0, y: 1, z: 0),

    Vertex(u: u, v: 0, x: 1, y: 0, z: 0),
    Vertex(u: u, v: v, x: 1, y: 1, z: 0),
    Vertex(u: 0, v: v, x: 0, y: 1, z: 0),
  ]

const
  BUF_WIDTH = 512
  SCR_WIDTH = 480
  SCR_HEIGHT = 272


var
  staticOffset = 0

proc getMemorySize(width, height: int, psm: cuint): cint =
  case psm
  of GU_PSM_T4:
    (width * height).cint shr 1
  of GU_PSM_T8:
    (width * height).cint
  of GU_PSM_5650, GU_PSM_5551, GU_PSM_4444, GU_PSM_T16:
    (2 * width * height).cint
  of GU_PSM_8888, GU_PSM_T32:
    (4 * width * height).cint
  else:
    0

proc getStaticVramBuffer(width, height: int, psm: cuint): pointer =
  let
    memSize = getMemorySize(width, height, psm)
  result = cast[pointer](staticOffset)
  staticOffset += memSize


var
  isOpen = true

proc exit_callback(arg1, arg2: cint, common: pointer): cint {.cdecl.} =
  # Exit callback
  isOpen = false
  return 0

proc CallbackThread(args: SceSize, argp: pointer): cint {.cdecl.} =
  # Callback thread
  let
    cbid = sceKernelCreateCallback("Exit Callback", exit_callback, nil)
  discard sceKernelRegisterExitCallback(cbid)

  discard sceKernelSleepThreadCB()
  return 0

proc setupCallbacks() =
  let
    thid = sceKernelCreateThread("update_thread", CallbackThread, 0x11, 0xFA0, 0, nil)
  if thid >= 0:
    discard sceKernelStartThread(thid, 0, nil)


proc main*() =
  setupCallbacks()

  # setup GU
  let
    fbp0 = getStaticVramBuffer(BUF_WIDTH, SCR_HEIGHT, GU_PSM_8888)
    fbp1 = getStaticVramBuffer(BUF_WIDTH, SCR_HEIGHT, GU_PSM_8888)
    zbp = getStaticVramBuffer(BUF_WIDTH, SCR_HEIGHT, GU_PSM_4444)

  sceGuInit()

  sceGuStart(GU_DIRECT, addr list[0])
  sceGuDrawBuffer(GU_PSM_8888, fbp0, BUF_WIDTH)
  sceGuDispBuffer(SCR_WIDTH, SCR_HEIGHT, fbp1, BUF_WIDTH)
  sceGuDepthBuffer(zbp, BUF_WIDTH)
  sceGuOffset(2048 - (SCR_WIDTH div 2), 2048 - (SCR_HEIGHT div 2))
  sceGuViewport(2048, 2048, SCR_WIDTH, SCR_HEIGHT)
  sceGuDepthRange(65535, 0)
  sceGuScissor(0, 0, SCR_WIDTH, SCR_HEIGHT)
  sceGuEnable(GU_SCISSOR_TEST)
  sceGuDepthFunc(GU_GEQUAL)
  sceGuEnable(GU_DEPTH_TEST)
  sceGuFrontFace(GU_CW)
  sceGuEnable(GU_CULL_FACE)
  sceGuEnable(GU_TEXTURE_2D)
  sceGuEnable(GU_CLIP_PLANES)
  discard sceGuFinish()
  discard sceGuSync(0, 0)

  discard sceDisplayWaitVblankStart()
  discard sceGuDisplay(GU_TRUE)

  var
    gameboy = init()
    isRunning = true
  while isOpen:
    var
      pad: SceCtrlData
    discard sceCtrlReadBufferPositive(addr pad, 1)
    gameboy.joypad[kA] = (pad.Buttons and PSP_CTRL_CIRCLE.cuint) != 0.cuint
    gameboy.joypad[kB] = (pad.Buttons and PSP_CTRL_CROSS.cuint) != 0.cuint
    gameboy.joypad[kStart] = (pad.Buttons and PSP_CTRL_START.cuint) != 0.cuint
    gameboy.joypad[kSelect] = (pad.Buttons and PSP_CTRL_SELECT.cuint) != 0.cuint
    gameboy.joypad[kUp] = (pad.Buttons and PSP_CTRL_UP.cuint) != 0.cuint
    gameboy.joypad[kLeft] = (pad.Buttons and PSP_CTRL_LEFT.cuint) != 0.cuint
    gameboy.joypad[kDown] = (pad.Buttons and PSP_CTRL_DOWN.cuint) != 0.cuint
    gameboy.joypad[kRight] = (pad.Buttons and PSP_CTRL_RIGHT.cuint) != 0.cuint

    let
      image = gameboy.frame(isRunning)
    for x in 0..<160:
      for y in 0..<144:
        let
          c = image[x, y]
        texure[y*256 + x] = [c[0], c[1], c[2], 255]

    sceGuStart(GU_DIRECT, addr list[0])

    # clear screen
    sceGuClearColor(0xff554433.cuint)
    sceGuClearDepth(0)
    sceGuClear(GU_COLOR_BUFFER_BIT or GU_DEPTH_BUFFER_BIT)

    # setup matrices for cube
    sceGumMatrixMode(GU_PROJECTION)
    sceGumLoadIdentity()
    sceGumOrtho(0, 1, 1, 0, 0, 1)

    sceGumMatrixMode(GU_VIEW)
    sceGumLoadIdentity()

    sceGumMatrixMode(GU_MODEL)
    sceGumLoadIdentity()
    var
      scale = ScePspFVector3(x: (SCR_HEIGHT / SCR_WIDTH) / (144 / 160), y: 1, z: 1)
      pos = ScePspFVector3(x: 0, y: 0, z: 0)
    sceGumScale(addr scale)
    sceGumTranslate(addr pos)

    # setup texture
    sceGuTexMode(GU_PSM_8888, 0, 0, 0)
    sceGuTexImage(0, 256, 256, 256, addr texure[0])
    sceGuTexFunc(GU_TFX_REPLACE, GU_TCC_RGB)
    sceGuTexFilter(GU_NEAREST, GU_NEAREST)
    sceGuTexScale(1.0, 1.0)
    sceGuTexOffset(0.0, 0.0)

    # draw cube
    sceGumDrawArray(GU_TRIANGLES, GU_TEXTURE_32BITF or GU_VERTEX_32BITF or GU_TRANSFORM_3D, 2*3, nil, addr vertices[0])

    discard sceGuFinish()
    discard sceGuSync(0, 0)

    discard sceDisplayWaitVblankStart()
    discard sceGuSwapBuffers()

  sceGuTerm()
  sceKernelExitGame()
