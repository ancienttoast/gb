# dear imgui: Platform Binding for SDL2
# This needs to be used along with a Renderer (e.g. DirectX11, OpenGL3, Vulkan..)
# (Info: SDL2 is a cross-platform general purpose library for handling windows, inputs, graphics context creation, etc.)
# (Requires: SDL 2.0. Prefer SDL 2.0.4+ for full feature support.)

# Implemented features:
#  [X] Platform: Mouse cursor shape and visibility. Disable with 'io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange'.
#  [X] Platform: Clipboard support.
#  [X] Platform: Keyboard arrays indexed using SDL_SCANCODE_* codes, e.g. ImGui::IsKeyPressed(SDL_SCANCODE_SPACE).
#  [X] Platform: Gamepad support. Enabled with 'io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad'.
# Missing features:
#  [ ] Platform: SDL2 handling of IME under Windows appears to be broken and it explicitly disable the regular Windows IME. You can restore Windows IME by compiling SDL with SDL_DISABLE_WINDOWS_IME.

# You can copy and use unmodified imgui_impl_* files in your project. See main.cpp for an example of using this.
# If you are new to dear imgui, read examples/README.txt and read the documentation at the top of imgui.cpp.
# https:#github.com/ocornut/imgui

# CHANGELOG
# (minor and older changes stripped away, please see git history for details)
#  2020-02-20: Inputs: Fixed mapping for ImGuiKey_KeyPadEnter (using SDL_SCANCODE_KP_ENTER instead of SDL_SCANCODE_RETURN2).
#  2019-12-17: Inputs: On Wayland, use SDL_GetMouseState (because there is no global mouse state).
#  2019-12-05: Inputs: Added support for ImGuiMouseCursor_NotAllowed mouse cursor.
#  2019-07-21: Inputs: Added mapping for ImGuiKey_KeyPadEnter.
#  2019-04-23: Inputs: Added support for SDL_GameController (if ImGuiConfigFlags_NavEnableGamepad is set by user application).
#  2019-03-12: Misc: Preserve DisplayFramebufferScale when main window is minimized.
#  2018-12-21: Inputs: Workaround for Android/iOS which don't seem to handle focus related calls.
#  2018-11-30: Misc: Setting up io.BackendPlatformName so it can be displayed in the About Window.
#  2018-11-14: Changed the signature of ImGui_ImplSDL2_ProcessEvent() to take a 'const SDL_Event*'.
#  2018-08-01: Inputs: Workaround for Emscripten which doesn't seem to handle focus related calls.
#  2018-06-29: Inputs: Added support for the ImGuiMouseCursor_Hand cursor.
#  2018-06-08: Misc: Extracted imgui_impl_sdl.cpp/.h away from the old combined SDL2+OpenGL/Vulkan examples.
#  2018-06-08: Misc: ImGui_ImplSDL2_InitForOpenGL() now takes a SDL_GLContext parameter.
#  2018-05-09: Misc: Fixed clipboard paste memory leak (we didn't call SDL_FreeMemory on the data returned by SDL_GetClipboardText).
#  2018-03-20: Misc: Setup io.BackendFlags ImGuiBackendFlags_HasMouseCursors flag + honor ImGuiConfigFlags_NoMouseCursorChange flag.
#  2018-02-16: Inputs: Added support for mouse cursors, honoring ImGui::GetMouseCursor() value.
#  2018-02-06: Misc: Removed call to ImGui::Shutdown() which is not available from 1.60 WIP, user needs to call CreateContext/DestroyContext themselves.
#  2018-02-06: Inputs: Added mapping for ImGuiKey_Space.
#  2018-02-05: Misc: Using SDL_GetPerformanceCounter() instead of SDL_GetTicks() to be able to handle very high framerate (1000+ FPS).
#  2018-02-05: Inputs: Keyboard mapping is using scancodes everywhere instead of a confusing mixture of keycodes and scancodes.
#  2018-01-20: Inputs: Added Horizontal Mouse Wheel support.
#  2018-01-19: Inputs: When available (SDL 2.0.4+) using SDL_CaptureMouse() to retrieve coordinates outside of client area when dragging. Otherwise (SDL 2.0.3 and before) testing for SDL_WINDOW_INPUT_FOCUS instead of SDL_WINDOW_MOUSE_FOCUS.
#  2018-01-18: Inputs: Added mapping for ImGuiKey_Insert.
#  2017-08-25: Inputs: MousePos set to -FLT_MAX,-FLT_MAX when mouse is unavailable/missing (instead of -1,-1).
#  2016-10-15: Misc: Added a void* user_data parameter to Clipboard function handlers.

import
  strutils,
  nimgl/imgui, sdl2, sdl2/gamecontroller

const
  # TODO: SDL_VERSION_ATLEAST(2,0,4)
  SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE = false
#func SDL_HAS_VULKAN() = SDL_VERSION_ATLEAST(2,0,6)

# Data
var
  g_Window: WindowPtr = nil
  g_Time: uint64 = 0
  g_MousePressed: array[3, bool] = [false, false, false]
  g_MouseCursors: array[ImGuiMouseCursor, CursorPtr]
  g_ClipboardTextData: cstring = nil
  g_MouseCanUseGlobalState: bool = true

proc igImplSdl2GetClipboardText(data: pointer): cstring {.cdecl.} =
  if g_ClipboardTextData != nil:
    freeClipboardText(g_ClipboardTextData)
  g_ClipboardTextData = getClipboardText()
  return g_ClipboardTextData

proc igImplSdl2SetClipboardText(data: pointer, text: cstring) {.cdecl.} =
  discard setClipboardText(text)

# You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
# - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application.
# - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application.
# Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
# If you have multiple SDL events and some of them are not meant to be used by dear imgui, you may need to filter events based on their windowID field.
proc igImplSdl2ProcessEvent*(event: Event): bool =
  let
    io = igGetIO()
  case event.kind:
  of MouseWheel:
    if event.wheel.x > 0: io.mouseWheelH += 1
    if event.wheel.x < 0: io.mouseWheelH -= 1
    if event.wheel.y > 0: io.mouseWheel += 1
    if event.wheel.y < 0: io.mouseWheel -= 1
    return true
  of MouseButtonDown:
    if event.button.button == BUTTON_LEFT: g_MousePressed[0] = true
    if event.button.button == BUTTON_RIGHT: g_MousePressed[1] = true
    if event.button.button == BUTTON_MIDDLE: g_MousePressed[2] = true
    return true
  of TextInput:
    io.addInputCharactersUTF8(addr event.text.text[0])
    return true
  of KeyDown, KeyUp:
    let
      key = event.key.keysym.scancode
    #IM_ASSERT(key >= 0 && key < IM_ARRAYSIZE(io.KeysDown));
    io.keysDown[key.int] = (event.kind == KeyDown)
    io.keyShift = (getModState() and KMOD_SHIFT) != 0
    io.keyCtrl = (getModState() and KMOD_CTRL) != 0
    io.keyAlt = (getModState() and KMOD_ALT) != 0
    when defined(windows):
      io.keySuper = false
    else:
      io.keySuper = (getModState() and KMOD_GUI) != 0
    return true
  else:
    return false

proc igSdl2Init(window: WindowPtr): bool =
  g_Window = window

  # Setup back-end capabilities flags
  let
    io = igGetIO()
  io.backendFlags = (io.backendFlags.int or ImGuiBackendFlags.HasMouseCursors.int).ImGuiBackendFlags       # We can honor GetMouseCursor() values (optional)
  io.backendFlags = (io.backendFlags.int or ImGuiBackendFlags.HasSetMousePos.int).ImGuiBackendFlags        # We can honor io.WantSetMousePos requests (optional, rarely used)
  io.backendPlatformName = "imgui_impl_sdl"

  # Keyboard mapping. ImGui will use those indices to peek into the io.KeysDown[] array.
  io.keyMap[ImGuiKey.Tab.int] = SDL_SCANCODE_TAB.int32
  io.keyMap[ImGuiKey.LeftArrow.int] = SDL_SCANCODE_LEFT.int32
  io.keyMap[ImGuiKey.RightArrow.int] = SDL_SCANCODE_RIGHT.int32
  io.keyMap[ImGuiKey.UpArrow.int] = SDL_SCANCODE_UP.int32
  io.keyMap[ImGuiKey.DownArrow.int] = SDL_SCANCODE_DOWN.int32
  io.keyMap[ImGuiKey.PageUp.int] = SDL_SCANCODE_PAGEUP.int32
  io.keyMap[ImGuiKey.PageDown.int] = SDL_SCANCODE_PAGEDOWN.int32
  io.keyMap[ImGuiKey.Home.int] = SDL_SCANCODE_HOME.int32
  io.keyMap[ImGuiKey.End.int] = SDL_SCANCODE_END.int32
  io.keyMap[ImGuiKey.Insert.int] = SDL_SCANCODE_INSERT.int32
  io.keyMap[ImGuiKey.Delete.int] = SDL_SCANCODE_DELETE.int32
  io.keyMap[ImGuiKey.Backspace.int] = SDL_SCANCODE_BACKSPACE.int32
  io.keyMap[ImGuiKey.Space.int] = SDL_SCANCODE_SPACE.int32
  io.keyMap[ImGuiKey.Enter.int] = SDL_SCANCODE_RETURN.int32
  io.keyMap[ImGuiKey.Escape.int] = SDL_SCANCODE_ESCAPE.int32
  io.keyMap[ImGuiKey.KeyPadEnter.int] = SDL_SCANCODE_KP_ENTER.int32
  io.keyMap[ImGuiKey.A.int] = SDL_SCANCODE_A.int32
  io.keyMap[ImGuiKey.C.int] = SDL_SCANCODE_C.int32
  io.keyMap[ImGuiKey.V.int] = SDL_SCANCODE_V.int32
  io.keyMap[ImGuiKey.X.int] = SDL_SCANCODE_X.int32
  io.keyMap[ImGuiKey.Y.int] = SDL_SCANCODE_Y.int32
  io.keyMap[ImGuiKey.Z.int] = SDL_SCANCODE_Z.int32

  # TODO: doesn't compile with emscripten
  when not defined(emscripten):
    io.setClipboardTextFn = igImplSdl2SetClipboardText
    io.getClipboardTextFn = igImplSdl2GetClipboardText
  io.clipboardUserData = nil

  # Load mouse cursors
  g_MouseCursors[ImGuiMouseCursor.Arrow] = createSystemCursor(SDL_SYSTEM_CURSOR_ARROW)
  g_MouseCursors[ImGuiMouseCursor.TextInput] = createSystemCursor(SDL_SYSTEM_CURSOR_IBEAM)
  g_MouseCursors[ImGuiMouseCursor.ResizeAll] = createSystemCursor(SDL_SYSTEM_CURSOR_SIZEALL)
  g_MouseCursors[ImGuiMouseCursor.ResizeNS] = createSystemCursor(SDL_SYSTEM_CURSOR_SIZENS)
  g_MouseCursors[ImGuiMouseCursor.ResizeEW] = createSystemCursor(SDL_SYSTEM_CURSOR_SIZEWE)
  g_MouseCursors[ImGuiMouseCursor.ResizeNESW] = createSystemCursor(SDL_SYSTEM_CURSOR_SIZENESW)
  g_MouseCursors[ImGuiMouseCursor.ResizeNWSE] = createSystemCursor(SDL_SYSTEM_CURSOR_SIZENWSE)
  g_MouseCursors[ImGuiMouseCursor.Hand] = createSystemCursor(SDL_SYSTEM_CURSOR_HAND)
  g_MouseCursors[ImGuiMouseCursor.NotAllowed] = createSystemCursor(SDL_SYSTEM_CURSOR_NO)

  # Check and store if we are on Wayland
  g_MouseCanUseGlobalState = "wayland" in $getCurrentVideoDriver()

  when defined(windows):
    var
      wmInfo: WMinfo
    getVersion(wmInfo.version)
    discard window.getWMInfo(wmInfo)
    #io.imeWindowHandle = wmInfo.info.win.window

  return true

proc igSdl2InitForOpenGL*(window: WindowPtr, sdl_gl_context: GLContextPtr): bool =
    #(void)sdl_gl_context // Viewport branch will need this.
    return igSdl2Init(window)

#[
bool ImGui_ImplSDL2_InitForVulkan(SDL_Window* window)
{
#if !SDL_HAS_VULKAN
    IM_ASSERT(0 && "Unsupported");
#endif
    return ImGui_ImplSDL2_Init(window);
}

bool ImGui_ImplSDL2_InitForD3D(SDL_Window* window)
{
#if !defined(_WIN32)
    IM_ASSERT(0 && "Unsupported");
#endif
    return ImGui_ImplSDL2_Init(window);
}

bool ImGui_ImplSDL2_InitForMetal(SDL_Window* window)
{
    return ImGui_ImplSDL2_Init(window);
}
]#

proc igSdl2Shutdown*() =
  g_Window = nil

  # Destroy last known clipboard data
  if g_ClipboardTextData != nil:
    freeClipboardText(g_ClipboardTextData)
  g_ClipboardTextData = nil

  # Destroy SDL mouse cursors
  for cursor in g_MouseCursors.mitems:
    freeCursor(cursor)
    cursor = nil


proc igImplSdl2UpdateMousePosAndButtons() =
  let
    io = igGetIO()

  # Set OS mouse position if requested (rarely used, only when ImGuiConfigFlags_NavEnableSetMousePos is enabled by user)
  if io.wantSetMousePos:
    g_Window.warpMouseInWindow(io.mousePos.x.cint, io.mousePos.y.cint)
  else:
    io.mousePos = ImVec2(x: float32.low, y: float32.low)

  var
    mx, my: cint
  let
    mouseButtons = sdl2.getMouseState(mx, my)
  io.mouseDown[0] = g_MousePressed[0] or (mouseButtons and SDL_BUTTON(BUTTON_LEFT)) != 0  # If a mouse press event came, always pass it as "mouse held this frame", so we don't miss click-release events that are shorter than 1 frame.
  io.mouseDown[1] = g_MousePressed[1] or (mouseButtons and SDL_BUTTON(BUTTON_RIGHT)) != 0
  io.mouseDown[2] = g_MousePressed[2] or (mouseButtons and SDL_BUTTON(BUTTON_MIDDLE)) != 0
  g_MousePressed[0] = false
  g_MousePressed[1] = false
  g_MousePressed[2] = false

  #if SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE && !defined(__EMSCRIPTEN__) && !defined(__ANDROID__) && !(defined(__APPLE__) && TARGET_OS_IOS)
  when SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE and not defined(emscripten):
    let
      focusedWindow = getKeyboardFocus()
    if g_Window == focused_window:
      if g_MouseCanUseGlobalState:
        # SDL_GetMouseState() gives mouse position seemingly based on the last window entered/focused(?)
        # The creation of a new windows at runtime and SDL_CaptureMouse both seems to severely mess up with that, so we retrieve that position globally.
        # Won't use this workaround when on Wayland, as there is no global mouse position.
        var
          wx, wy: cint
        focusedWindow.getPosition(wx, wy)
        #getGlobalMouseState(mx, my)
        mx -= wx
        my -= wy
      io.mousePos = ImVec2(x: mx.float32, y: my.float32)

    # SDL_CaptureMouse() let the OS know e.g. that our imgui drag outside the SDL window boundaries shouldn't e.g. trigger the OS window resize cursor.
    # The function is only supported from SDL 2.0.4 (released Jan 2016)
    let
      anyMouseButtonDown = igIsAnyMouseDown()
    discard captureMouse(anyMouseButtonDown.Bool32)
  else:
    #if (g_Window.getFlags() and SDL_WINDOW_INPUT_FOCUS) == 0:
    io.mousePos = ImVec2(x: mx.float32, y: my.float32)

proc igImplSdl2UpdateMouseCursor() =
  let
    io = igGetIO()
  if (io.configFlags.int and ImGuiConfigFlags.NoMouseCursorChange.int) == 0:
    return

  let
    imguiCursor = igGetMouseCursor()
  if io.mouseDrawCursor or imgui_cursor == ImGuiMouseCursor.None:
    # Hide OS mouse cursor if imgui is drawing it or if it wants no cursor
    showCursor(false)
  else:
    # Show OS mouse cursor
    setCursor(if g_MouseCursors[imgui_cursor] != nil: g_MouseCursors[imgui_cursor] else: g_MouseCursors[ImGuiMouseCursor.Arrow])
    showCursor(true)

proc igImplSdl2UpdateGamepads() =
  let
    io = igGetIO()
  #memset(io.NavInputs, 0, sizeof(io.NavInputs))
  if (io.configFlags.int and ImGuiConfigFlags.NavEnableGamepad.int) == 0:
    return

  # Get gamepad
  var
    gameController = gameControllerOpen(0)
  if game_controller != nil:
    io.backendFlags = (io.backendFlags.int and (not ImGuiBackendFlags.HasGamepad.int)).ImGuiBackendFlags
    return

  # Update gamepad inputs
  #[
  #define MAP_BUTTON(NAV_NO, BUTTON_NO)       { io.NavInputs[NAV_NO] = (SDL_GameControllerGetButton(game_controller, BUTTON_NO) != 0) ? 1.0f : 0.0f; }
  #define MAP_ANALOG(NAV_NO, AXIS_NO, V0, V1) { float vn = (float)(SDL_GameControllerGetAxis(game_controller, AXIS_NO) - V0) / (float)(V1 - V0); if (vn > 1.0f) vn = 1.0f; if (vn > 0.0f && io.NavInputs[NAV_NO] < vn) io.NavInputs[NAV_NO] = vn; }
  const int thumb_dead_zone = 8000;           // SDL_gamecontroller.h suggests using this value.
  MAP_BUTTON(ImGuiNavInput_Activate,      SDL_CONTROLLER_BUTTON_A);               // Cross / A
  MAP_BUTTON(ImGuiNavInput_Cancel,        SDL_CONTROLLER_BUTTON_B);               // Circle / B
  MAP_BUTTON(ImGuiNavInput_Menu,          SDL_CONTROLLER_BUTTON_X);               // Square / X
  MAP_BUTTON(ImGuiNavInput_Input,         SDL_CONTROLLER_BUTTON_Y);               // Triangle / Y
  MAP_BUTTON(ImGuiNavInput_DpadLeft,      SDL_CONTROLLER_BUTTON_DPAD_LEFT);       // D-Pad Left
  MAP_BUTTON(ImGuiNavInput_DpadRight,     SDL_CONTROLLER_BUTTON_DPAD_RIGHT);      // D-Pad Right
  MAP_BUTTON(ImGuiNavInput_DpadUp,        SDL_CONTROLLER_BUTTON_DPAD_UP);         // D-Pad Up
  MAP_BUTTON(ImGuiNavInput_DpadDown,      SDL_CONTROLLER_BUTTON_DPAD_DOWN);       // D-Pad Down
  MAP_BUTTON(ImGuiNavInput_FocusPrev,     SDL_CONTROLLER_BUTTON_LEFTSHOULDER);    // L1 / LB
  MAP_BUTTON(ImGuiNavInput_FocusNext,     SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);   // R1 / RB
  MAP_BUTTON(ImGuiNavInput_TweakSlow,     SDL_CONTROLLER_BUTTON_LEFTSHOULDER);    // L1 / LB
  MAP_BUTTON(ImGuiNavInput_TweakFast,     SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);   // R1 / RB
  MAP_ANALOG(ImGuiNavInput_LStickLeft,    SDL_CONTROLLER_AXIS_LEFTX, -thumb_dead_zone, -32768);
  MAP_ANALOG(ImGuiNavInput_LStickRight,   SDL_CONTROLLER_AXIS_LEFTX, +thumb_dead_zone, +32767);
  MAP_ANALOG(ImGuiNavInput_LStickUp,      SDL_CONTROLLER_AXIS_LEFTY, -thumb_dead_zone, -32767);
  MAP_ANALOG(ImGuiNavInput_LStickDown,    SDL_CONTROLLER_AXIS_LEFTY, +thumb_dead_zone, +32767);

  io.BackendFlags |= ImGuiBackendFlags_HasGamepad;
  #undef MAP_BUTTON
  #undef MAP_ANALOG
  ]#

proc igImplSdl2NewFrame*(window: WindowPtr) =
  let
    io = igGetIO()
  #IM_ASSERT(io.Fonts->IsBuilt() && "Font atlas not built! It is generally built by the renderer back-end. Missing call to renderer _NewFrame() function? e.g. ImGui_ImplOpenGL3_NewFrame().");

  # Setup display size (every frame to accommodate for window resizing)
  var
    w, h: cint
    displayW, displayH: cint
  window.getSize(w, h)
  window.glGetDrawableSize(displayW, displayH)
  io.displaySize = ImVec2(x: w.float32, y: h.float32)
  if w > 0 and h > 0:
    io.displayFramebufferScale = ImVec2(x: displayW.float32 / w.float32, y: displayH.float32 / h.float32)

  # Setup time step (we don't use SDL_GetTicks() because it is using millisecond resolution)
  let
    # TODO: initialize this only once
    frequency = getPerformanceFrequency()
    currentTime = getPerformanceCounter()
  io.deltaTime = if g_Time > 0: ((currentTime - g_Time).float64 / frequency.float64).float32 else: 1'f32 / 60'f32
  g_Time = currentTime

  igImplSdl2UpdateMousePosAndButtons()
  igImplSdl2UpdateMouseCursor()

  # Update game controllers (if enabled and available)
  igImplSdl2UpdateGamepads()
