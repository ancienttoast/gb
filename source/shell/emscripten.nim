proc hackedRawProc[T: proc](x: T): pointer {.noSideEffect, inline.} =
  ## Retrieves the raw proc pointer of the closure `x`. This is
  ## useful for interfacing closures with C.
  {.emit: """
  `result` = (void *)`x`.ClP_0;
  """.}

type
  em_arg_callback_func = proc(data: pointer) {.cdecl.}
proc emscripten_set_main_loop_arg(f: em_arg_callback_func, data: pointer, fps: cint, simulate_infinite_loop: cint) {.importc.}
proc emscripten_cancel_main_loop*() {.importc.}

proc emscripten_set_main_loop_arg*(f: proc(), fps: cint, simulate_infinite_loop: cint) =
  let
    env = protect(f.rawEnv)
  emscripten_set_main_loop_arg(cast[em_arg_callback_func](f.hackedRawProc), env.data, fps, simulate_infinite_loop)
  dispose(env)