when defined(profiler):
  import nimprof

when defined(wasm):
  import shell/simple/wasm
elif defined(psp):
  import shell/simple/psp
else:
  import shell/simple/pc

main()
