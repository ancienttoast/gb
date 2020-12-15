##[

Gameboy
=======

Models
----------

========  =========================
  Name      Model
========  =========================
  DMG       Game Boy
  MGB       Game Boy Pocket
  SGB       Super Game Boy
  SGB2      Super Game Boy 2
  CGB       Game Boy Color
========  =========================

]##
import
  std/[times, monotimes],
  common/cart,
  dmg/[dmg, joypad],
  cgb/cgb



type
  InputKey* = enum
    iRight,
    iLeft,
    iUp,
    iDown,
    iA,
    iB,
    iSelect,
    iStart

const
  DmgKeyInputMap: array[InputKey, JoypadKey] = [
    kRight, kLeft, kUp, kDown,
    kA, kB,
    kSelect, kStart
  ]

func `$`*(key: InputKey): string =
  result = system.`$`(key)
  result = result[1..result.high]


type
  GameboyKind* = enum
    gkDMG,
    gkMGB,
    gkSGB,
    gkSGB2,
    gkCGB

  GameboyState* = object
    #time*: DateTime
    cart*: string
    case kind*: GameboyKind
    of gkDMG:
      dmgState*: DmgState
    of gkCGB:
      cgbState*: CgbState
    else:
      discard

  Gameboy* = ref object
    case kind*: GameboyKind
    of gkDMG:
      dmg*: Dmg
    of gkCGB:
      cgb*: Cgb
    else:
      discard

proc input*(self: Gameboy, input: InputKey, isPressed: bool) =
  assert self.kind in {gkDMG, gkCGB}
  case self.kind
  of gkDMG:
    self.dmg.joypad[DmgKeyInputMap[input]] = isPressed
  of gkCGB:
    self.cgb.joypad[DmgKeyInputMap[input]] = isPressed
  else:
    discard

proc save*(self: Gameboy): GameboyState =
  assert self.kind in {gkDMG, gkCGB}
  result = GameboyState(
    #time: now(),
    kind: self.kind
  )
  case self.kind
  of gkDMG:
    result.dmgState = self.dmg.save()
    result.cart = $self.dmg.cart.header
  of gkCGB:
    result.cgbState = self.cgb.save()
    result.cart = $self.cgb.cart.header
  else:
    discard

proc load*(self: Gameboy, state: GameboyState) =
  assert self.kind in {gkDMG, gkCGB}
  assert self.kind == state.kind
  case self.kind
  of gkDMG:
    self.dmg.load(state.dmgState)
  of gkCGB:
    self.cgb.load(state.cgbState)
  else:
    discard

proc step*(self: Gameboy): bool =
  ## Advance the device by a single cpu instruction.
  assert self.kind in {gkDMG, gkCGB}
  case self.kind
  of gkDMG:
    result = self.dmg.step()
  of gkCGB:
    result = self.cgb.step()
  else:
    discard

proc stepFrame*(self: Gameboy) =
  ## Advance the device by a signle frame.
  var
    needsRedraw = false
  while not needsRedraw:
    needsRedraw = needsRedraw or self.step()

proc frame*(self: Gameboy, frameLimit: Natural = 200, msLimit = 16): int =
  ## Advance the device by multiple frames. This will run for at most `msLimit` milliseconds or the
  ## number of frames specified in `frameLimit`, whichever happens first.
  ##
  ## If `frameLimit` is 0 200 will be used instead.
  ## If `msLimit`is 0 16 will be used
  let
    frameLimit = if frameLimit == 0: 200 else: frameLimit
    timeLimit = if msLimit == 0: initDuration(milliseconds = 16) else: initDuration(milliseconds = msLimit)
  var
    count = 0
    timer = getMonoTime()
  while count < frameLimit and (getMonoTime() - timer) < timeLimit:
    self.stepFrame()
    count += 1
  count


proc newGameboy*(rom: string, bootRom = ""): Gameboy =
  let
    cart = readCartHeader(rom)
  if cart.isCgbOnly:
    result = Gameboy(
        kind: gkCGB,
        cgb: newCgb(bootRom)
      )
    result.cgb.reset(rom)
  else:
    result = Gameboy(
        kind: gkDMG,
        dmg: newDmg(bootRom)
      )
    result.dmg.reset(rom)