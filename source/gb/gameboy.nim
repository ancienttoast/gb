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
  std/times,
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

proc step*(self: Gameboy): bool =
  assert self.kind == gkDMG
  self.dmg.step()

proc input*(self: Gameboy, input: InputKey, isPressed: bool) =
  assert self.kind == gkDMG
  self.dmg.joypad[DmgKeyInputMap[input]] = isPressed


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
