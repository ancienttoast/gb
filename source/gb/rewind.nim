import
  gameboy



type
  History* = ref object
    states: seq[GameboyState]
    current: int
    maxSize: int

proc advance*(self: History, gameboy: Gameboy) =
  if self.maxSize != 0 and self.states.len >= self.maxSize:
    self.current = (self.current + 1) mod self.maxSize
    self.states[self.current] = gameboy.save()
  else:
    self.states.add(gameboy.save())
    self.current += 1

proc restore*(self: History, gameboy: Gameboy, i: int) =
  gameboy.load(self.states[(self.current + i) mod self.maxSize])
  self.current = i

proc clear*(self: History) =
  self.states = newSeq[GameboyState]()
  self.current = 0

proc len*(self: History): int =
  self.states.len

proc sizeInBytes*(self: History): int =
  self.states.len * GameboyState.sizeof

proc index*(self: History): int =
  self.current

proc newHistory*(maxSize = 1024): History =
  History(
    states: newSeq[GameboyState](),
    current: 0,
    maxSize: maxSize
  )
