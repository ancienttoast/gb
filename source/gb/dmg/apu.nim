##[

  Audio Processing Unit
  =====================

  * `https://gbdev.io/pandocs/#sound-controller`_
  * `https://flothesof.github.io/gameboy-sounds-in-python.html`_
  * `https://github.com/Humpheh/goboy/blob/master/pkg/apu/apu.go`_
  * `https://gist.github.com/armornick/3447121`_
  * `http://emudev.de/gameboy-emulator/bleeding-ears-time-to-add-audio/`_
  * `http://www.devrs.com/gb/files/hosted/GBSOUND.txt`_
  * `https://gbdev.gg8.se/wiki/articles/Gameboy_sound_hardware`_

]##
import
  std/math,
  mem, gb/common/util



func isDivByPowerOf2[T](value: T, power: int): bool =
  (value and ((1.T shl power.T) - 1.T)) == 0



type
  Ch3Level = enum
    cl0   = 0
    cl100 = 1
    cl50  = 2
    cl25  = 3

  ApuStateIo* = tuple
    # Channel 1
    ch1Sweep:      uint8  ## 0xff10  Channel 1 Sweep register (R/W)
    ch1Len:        uint8  ## 0xff11  Channel 1 Sound length/Wave pattern duty (R/W)
    ch1Envelope:   uint8  ## 0xff12  Channel 1 Volume Envelope (R/W)
    ch1FrequencyL: uint8  ## 0xff13  Channel 1 Frequency lo (Write Only)
    ch1FrequencyH: uint8  ## 0xff14  Channel 1 Frequency hi (R/W)

    unused0:       uint8  ## 0xff15

    # Channel 2
    ch2Len:        uint8  ## 0xff16  Channel 2 Sound Length/Wave Pattern Duty (R/W)
    ch2Envelope:   uint8  ## 0xff17  Channel 2 Volume Envelope (R/W)
    ch2FrequencyL: uint8  ## 0xff18  Channel 2 Frequency lo data (W)
    ch2FrequencyH: uint8  ## 0xff19  Channel 2 Frequency hi data (R/W)

    # Channel 3
    ch3Ctr:        uint8  ## 0xff1a  Channel 3 Sound on/off (R/W)
                          ##   bit 7 - On/Off  (0=Stop, 1=Playback) (R/W)
    ch3Len:        uint8  ## 0xff1b  Channel 3 Sound Length
    ch3Lev:        uint8  ## 0xff1c  Channel 3 Select output level (R/W)
                          ##   bit 6-5 - Select output level (see _Ch3Level_ for possible values) (R/W)
    ch3FrequencyL: uint8  ## 0xff1d  Channel 3 Frequency's lower data (W)
                          ##   Lower 8 bits of the 11 bit frequency
    ch3FrequencyH: uint8  ## 0xff1e  Channel 3 Frequency's higher data (R/W)
                          ##   bit 7   - Initial (1=Restart Sound)     (W)
                          ##   bit 6   - Counter/consecutive selection (R/W)
                          ##             (1=Stop output when length in _ch3Len_ expires)
                          ##   bit 2-0 - Frequency's higher 3 bits (x) (W)

    unused1:       uint8  ## 0xff1f

    # Channel 4
    ch4Len:        uint8  ## 0xff20  Channel 4 Sound Length (R/W)
                          ##   Sound Length = (64-t1)*(1/256) seconds The Length value is used only if Bit 6 in NR44 is set.
                          ##     bit 5-0 - Sound length data (t1: 0-63)
    ch4Envelope:   uint8  ## 0xff21  Channel 4 Volume Envelope (R/W)
                          ##   bit 7-4 - Initial Volume of envelope (0-0Fh) (0=No Sound)
                          ##   bit 3   - Envelope Direction (0=Decrease, 1=Increase)
                          ##   bit 2-0 - Number of envelope sweep (n: 0-7)
                          ##     Length of 1 step = n*(1/64) seconds. If zero, stop envelope operation.

    unused2:       uint8  ## 0xff22
    unused3:       uint8  ## 0xff23

    # Control registers
    channelCtrl:    uint8 ## 0xff24  Channel control / ON-OFF / Volume (R/W)
                          ##   bit 7   - Output Vin to SO2 terminal (1=Enable)
                          ##   bit 6-4 - SO2 output level (volume)  (0-7)
                          ##   bit 3   - Output Vin to SO1 terminal (1=Enable)
                          ##   bit 2-0 - SO1 output level (volume)  (0-7)
    selectionCtrl:  uint8 ## 0xff25  Selection of Sound output terminal (R/W)
                          ##   bit 7 - Output sound 4 to SO2 terminal
                          ##   bit 6 - Output sound 3 to SO2 terminal
                          ##   bit 5 - Output sound 2 to SO2 terminal
                          ##   bit 4 - Output sound 1 to SO2 terminal
                          ##   bit 3 - Output sound 4 to SO1 terminal
                          ##   bit 2 - Output sound 3 to SO1 terminal
                          ##   bit 1 - Output sound 2 to SO1 terminal
                          ##   bit 0 - Output sound 1 to SO1 terminal
    soundCtrl:      uint8 ## 0xff26  Sound on/off
                          ##   bit 7 - All sound on/off (0=stop all sound circuits) (R/W)
                          ##   bit 3 - Sound 4 ON flag (R)
                          ##   bit 2 - Sound 3 ON flag (R)
                          ##   bit 1 - Sound 2 ON flag (R)
                          ##   bit 0 - Sound 1 ON flag (R)

    unused4:        array[9, uint8]
                          ## 0xff27-0xff2f
    wav:            array[16, uint8]
                          ## 0xff30-0xff3f  Wave Pattern RAM
  
  ApuState* = tuple
    io: ApuStateIo
    ch3Buffer: seq[float32]
    ch3Position: int
    fs: uint16            ## Frame sequencer 512Hz (8192 cpu cycles)
                          ##   Length ctrl: 256Hz (16384 cpu cycles)
                          ##   Sweep: 128Hz (32768 cpu cycles)
                          ##   Vol envelope: 64Hz (65 536 cpu cycles)
  
  Apu* = ref object
    mcu: Mcu
    state*: ApuState


func isCh3On(self: ApuStateIo): bool =
  self.ch3Ctr.testBit(7)

func ch3TurnOff(self: var ApuStateIo) =
  self.ch3Ctr.clearBit(7)

func ch3Level(self: ApuStateIo): Ch3Level =
  self.ch3Lev.extract(5, 6).Ch3Level

func ch3Freq(self: ApuStateIo): uint16 =
  self.ch3FrequencyL.uint16 or
  (self.ch3FrequencyH.extract(0, 2).uint16 shl 8)

func isCh3LenEnabled(self: ApuStateIo): bool =
  self.ch3FrequencyH.testBit(6)

func ch3Sample(self: ApuStateIo, i: int): float32 =
  let
    b = self.wav[i div 2]
  if i.testBit(0):
    b.extract(0, 3).float32
  else:
    b.extract(4, 7).float32

func ch3Step(self: var ApuState, cycles: int) =
  const
    LevelMultiplier: array[Ch3Level, float] = [0.0, 1.0, 0.5, 0.25]
  for i in 0..<cycles:
    if self.io.isCh3On:
      self.fs += 1
      if self.fs.isDivByPowerOf2(14):
        self.io.ch3Len = max(self.io.ch3Len - 1, 0)
      if self.io.isCh3LenEnabled and self.io.ch3Len == 0:
        self.io.ch3TurnOff()
      let
        level = LevelMultiplier[self.io.ch3Level]


func isOn(self: ApuState): bool =
  self.io.soundCtrl.testBit(7)

proc step*(self: Apu, cycles: int) =
  if not self.state.isOn:
    self.state.ch3Step(cycles)


proc setupMemHandler*(mcu: Mcu, self: Apu) =
  mcu.setHandler(msApu, addr self.state.io)
  self.mcu = mcu

proc newApu*(mcu: Mcu): Apu =
  result = Apu()
  mcu.setupMemHandler(result)



proc square*(x: float, period = 128.0, amplitude = 100.0): float =
  # Force positive argument.
  let
    neg = x < 0.0
    xx  = if neg: -x else: x

  # Scale the argument and compute the return value.
  let
    x_scaled = xx - floor((xx * 0.5) / period) * period
    ret_val  = if x_scaled < period / 2.0: amplitude else: -amplitude

  # Antisymmetric square wave.
  if not neg: ret_val else: -ret_val





import
  nimgl/imgui

proc uiApu*() =
  igBegin("apu")
  var
    data: array[1024, float32]
    t = 0.0
  for d in data.mitems:
    d = square(t, 1, 1).float32
    t += 10 / 1024
  igPlotLines("square", addr data[0], data.len.int32, scale_min = 0, scale_max = 1, graph_size = ImVec2(x: 0, y: 50))
  igEnd()
