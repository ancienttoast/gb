when defined(wasm):
  import simple/wasm
elif defined(psp):
  import simple/psp
else:
  import simple/pc

main()
