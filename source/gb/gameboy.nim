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
  dmg/[dmg, joypad]



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

type
  GameboyKind* = enum
    gkDMG,
    gkMGB,
    gkSGB,
    gkSGB2,
    gkCGH

  GameboyState* = object
    time*: DateTime
    case kind: GameboyKind
    of gkDMG:
      dmgState: DmgState
    else:
      discard

  Gameboy* = ref object
    case kind*: GameboyKind
    of gkDMG:
      dmg*: Dmg
    else:
      discard

proc load*(self: Gameboy, rom = "") =
  assert self.kind == gkDMG
  self.dmg.reset(rom)

proc input*(self: Gameboy, input: InputKey, isPressed: bool) =
  assert self.kind == gkDMG
  self.dmg.joypad[DmgKeyInputMap[input]] = isPressed

proc step*(self: Gameboy): bool =
  assert self.kind == gkDMG
  self.dmg.step()

proc stepFrame*(self: Gameboy) =
  var
    needsRedraw = false
  while not needsRedraw:
    needsRedraw = needsRedraw or self.step()

proc frame*(self: Gameboy, frameLimit: Natural = 200, msLimit = 16): int =
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

proc save*(self: Gameboy): GameboyState =
  assert self.kind == gkDMG
  result.time = now()
  result.dmgState = self.dmg.save()

proc load*(self: Gameboy, state: GameboyState) =
  assert self.kind == gkDMG
  assert state.kind == gkDMG
  self.dmg.load(state.dmgState)


proc newGameboy*(bootRom = ""): Gameboy =
  Gameboy(
    kind: gkDMG,
    dmg: newDmg(bootRom)
  )
