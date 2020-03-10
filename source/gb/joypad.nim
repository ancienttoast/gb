##[

  * `https://gbdev.gg8.se/wiki/articles/Joypad_Input`_

]##
import
  std/bitops,
  mem



type
  JoypadKey* = enum
    kRight,
    kLeft,
    kUp,
    kDown,
    kA,
    kB,
    kSelect,
    kStart
  
  JoypadRegisterMode = enum
    rmDirectionKeys,
    rmButtonKeys
  
  JoypadState* = tuple
    mode: JoypadRegisterMode
    keys: array[JoypadKey, bool]
  
  Joypad* = ref object
    state*: JoypadState


func calcState(state: JoypadState): uint8 =
  ## bit 7 - Not used
  ## bit 6 - Not used
  ## bit 5 - P15 Select Button Keys      (0=Select)
  ## bit 4 - P14 Select Direction Keys   (0=Select)
  ## bit 3 - P13 Input Down  or Start    (0=Pressed) (Read Only)
  ## bit 2 - P12 Input Up    or Select   (0=Pressed) (Read Only)
  ## bit 1 - P11 Input Left  or Button B (0=Pressed) (Read Only)
  ## bit 0 - P10 Input Right or Button A (0=Pressed) (Read Only)
  let
    dist = if state.mode == rmDirectionKeys: 0 else: 4
  for i in 0..3:
    let
      key = (i + dist).JoypadKey
    if not state.keys[key]:
      setBit(result, i)
    

proc pushHandler*(mcu: Mcu, joypad: Joypad) =
  mcu.pushHandler MemHandler(
    read: proc(address: MemAddress): uint8 =
      joypad.state.calcState()
    ,
    write: proc(address: MemAddress, value: uint8) =
      if testBit(value, 5):
        joypad.state.mode = rmButtonKeys
      if testBit(value, 4):
        joypad.state.mode = rmDirectionKeys
    ,
    area: 0xff00.MemAddress .. 0xff00.MemAddress
  )

proc newJoypad*(mcu: Mcu): Joypad =
  result = Joypad()
  mcu.pushHandler(result)

proc setKey*(self: Joypad, key: JoypadKey, state: bool) =
  self.state.keys[key] = state
