import
  gameboy



type
  CircularSeq[T] = object
    data: seq[T]
    start: int
    maxSize: int

func size(self: CircularSeq): int =
  self.maxSize

func len(self: CircularSeq): int =
  self.data.len

func `[]`[T](self: CircularSeq[T], i: int): T =
  self.data[(self.start + i) mod self.maxSize]

func add[T](self: var CircularSeq[T], value: T) =
  if self.data.len >= self.maxSize:
    let
      i = (self.start + self.maxSize - 1) mod self.maxSize
    self.data[i] = value
    self.start = (self.start + 1) mod self.maxSize
  else:
    self.data.add(value)

func initCircularSeq[T](size: int): CircularSeq[T] =
  CircularSeq[T](
    data: newSeq[T](),
    start: 0,
    maxSize: size
  )


type
  History* = ref object
    states: CircularSeq[GameboyState]
    current: int

proc advance*(self: History, gameboy: Gameboy) =
  self.states.add gameboy.save()
  self.current = (self.current + 1) mod self.states.size

proc restore*(self: History, gameboy: Gameboy, i: int) =
  gameboy.load(self.states[i])
  self.current = i

proc clear*(self: History) =
  self.states = initCircularSeq[GameboyState](self.states.size)
  self.current = 0

proc len*(self: History): int =
  self.states.len

proc high*(self: History): int =
  self.len - 1

proc sizeInBytes*(self: History): int =
  self.states.len * GameboyState.sizeof

proc index*(self: History): int =
  self.current

proc newHistory*(maxSize = 1024): History =
  History(
    states: initCircularSeq[GameboyState](maxSize),
    current: 0
  )
