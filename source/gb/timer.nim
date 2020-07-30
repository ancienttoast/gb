##[

  Timer and Divider Registers
  ===========================

  Memory map
  ----------

  ======= ==== ======================
  Address Name Description
  ------- ---- ----------------------
  0xff04  DIV  Divider Register (R/W)
  0xff05  TIMA Timer counter (R/W)
  0xff06  TMA  Timer Modulo (R/W)
  0xff07  TAC  Timer Control (R/W)

]##
import
  mem, interrupt, util



type
  TimerCycleCounter = range[0..1024]
  TimerState* = tuple
    divider:  uint8   ## 0xff04  Automatically incremented. Writing to this resets it to 0.
    tima:     uint8   ## 0xff05  Incremented by the frequency specified by _tac_ (0xff07). On overflow an
                      ##   interrupt is raised by setting bit 2 in the IF register (0xff0f) then the value
                      ##   is reset to _tma_ (0xff06).
    tma:      uint8   ## 0xff06  The new value of _tima_ (0xff05) on overflow.
    tac:      uint8   ## 0xff07  Timer control register
                      ##   bit 2   - Timer enable (only affects _tima_, the divider is always counting)
                      ##   bit 1-0 - Frequency select
                      ##             00: CPU Clock / 1024
                      ##             01: CPU Clock / 16
                      ##             10: CPU Clock / 64
                      ##             11: CPU Clock / 256
    counter:  TimerCycleCounter

  Timer* = ref object
    state*: TimerState
    mcu: Mcu

const
  DividerFrequency = 256 ## CPU Clock / 256 = 16384Hz
  TimerFrequencies = [1024, 16, 64, 256] ## CPU Clock / x


proc isEnabled(self: Timer): bool =
  self.state.tac.testBit(2)

proc speed(self: Timer): int =
  TimerFrequencies[self.state.tac and 0b00000011]

proc step*(self: Timer) =
  self.state.counter += 1

  if self.state.counter mod DividerFrequency == 0:
    self.state.divider += 1
  
  if self.isEnabled and self.state.counter.int mod self.speed == 0:
    self.state.tima += 1
    if self.state.tima == 0:
      self.state.tima = self.state.tma
      self.mcu.raiseInterrupt(iTimer)
  
  if self.state.counter == TimerCycleCounter.high:
    self.state.counter = TimerCycleCounter.low

proc setupMemHandler*(mcu: Mcu, self: Timer) =
  mcu.setHandler(msTimer,
    MemHandler(
      read: proc(address: MemAddress): uint8 =
        case address
        of 0xff04: self.state.divider
        of 0xff05: self.state.tima
        of 0xff06: self.state.tma
        of 0xff07: self.state.tac
        else: 0'u8,
      write: proc(address: MemAddress, value: uint8) =
        case address
        of 0xff04: self.state.divider = 0
        of 0xff05: self.state.tima = value
        of 0xff06: self.state.tma = value
        of 0xff07: self.state.tac = value
        else: discard
    )
  )

proc newTimer*(): Timer =
  Timer()

proc newTimer*(mcu: Mcu): Timer =
  result = newTimer()
  result.mcu = mcu
  mcu.setupMemHandler(result)
