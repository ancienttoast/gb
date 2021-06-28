##[

  Audio Processing Unit
  =====================

  * `https://gbdev.io/pandocs/#sound-controller`_
  * `http://emudev.de/gameboy-emulator/bleeding-ears-time-to-add-audio/`_
  * `http://www.devrs.com/gb/files/hosted/GBSOUND.txt`_
  * `https://nightshade256.github.io/2021/03/27/gb-sound-emulation.html`_

]##
import
  sdl2/audio,
  std/math,
  mem, gb/common/util



func isDivByPowerOf2[T](value: T, power: int): bool =
  (value and ((1.T shl power.T) - 1.T)) == 0



type
  Envelope = tuple
    ## Volume envelope unit.
    ##
    ## Needs access to the envelope registers [NR12 / NR22 / NR42].
    ##   bit 7-4 - Initial Volume of envelope (0-0Fh) (0=No Sound)
    ##   bit 3   - Envelope Direction (0=Decrease, 1=Increase)
    ##   bit 2-0 - Number of envelope sweep (n: 0-7) If zero, stop envelope operation.
    timer: int
    volume: uint8

func initialVolume(chEnvelope: uint8): uint8 =
  chEnvelope.extract(4, 7)

func volumeIsIncresing(chEnvelope: uint8): bool =
  chEnvelope.testBit(3)

func envelopePeriod(chEnvelope: uint8): int =
  chEnvelope.extract(0, 2).int

func step(self: var Envelope, chEnvelope: uint8) =
  if self.timer != 0:
    if self.timer > 0:
      self.timer -= 1
    
    if self.timer == 0:
      self.timer = chEnvelope.envelopePeriod()

      let
        isVoluemIncreasing = chEnvelope.volumeIsIncresing()
      if (self.volume < 0xF and isVoluemIncreasing) or (self.volume > 0x0 and not isVoluemIncreasing):
        if isVoluemIncreasing:
          self.volume += 1
        else:
          self.volume -= 1

func initEnvelope(chEnvelope: uint8): Envelope =
  result.volume = chEnvelope.initialVolume()
  result.timer = chEnvelope.envelopePeriod()



type
  Sweep = tuple
    ## Frequency sweep unit.
    ##
    ## Only used by channel 1 [NR10].
    ##   bit 6-4 - Sweep Time
    ##   bit 3   - Sweep Increase/Decrease (0=Increase, 1=Decrease)
    ##   bit 2-0 - Number of sweep shift (n: 0-7)
    isEnabled: bool
    shadowFreq: uint16
    timer: int

func sweepPeriod(chSweep: uint8): int =
  chSweep.extract(4, 6).int

func freqIsDecreasing(chSweep: uint8): bool =
  chSweep.testBit(3)

func sweepShift(chSweep: uint8): uint16 =
  chSweep.extract(0, 2).uint16

func resetTimer(self: var Sweep, chSweep: uint8) =
  self.timer = chSweep.sweepPeriod()
  if self.timer == 0:
    self.timer = 8

func calcNewFreq(self: Sweep, chSweep: uint8): tuple[freq: uint16, shouldDisable: bool] =
  let
    d = self.shadowFreq shr chSweep.sweepShift()
  if chSweep.freqIsDecreasing():
    result.freq = self.shadowFreq - d
  else:
    result.freq = self.shadowFreq + d
  
  # Overflow check
  result.shouldDisable = result.freq > 2047

func step(self: var Sweep, chSweep: uint8): tuple[freq: uint16, shouldDisable: bool, freqChanged: bool] =
  if self.timer > 0:
    self.timer -= 1
  
  if self.timer == 0:
    self.resetTimer(chSweep)
    
    if self.isEnabled and chSweep.sweepShift() > 0:
      let
        (newFreq, _) = self.calcNewFreq(chSweep)
      if newFreq <= 2048 and chSweep.sweepShift() > 0:
        result.freq = newFreq
        self.shadowFreq = newFreq

        # Do the overflow check again
        let
          (_, shouldDisable) = self.calcNewFreq(chSweep)
        result.shouldDisable = shouldDisable
        result.freqChanged = true

func initSweep(chSweep: uint8, freq: uint16): Sweep =
  result.shadowFreq = freq
  result.isEnabled = chSweep.sweepPeriod() != 0 or chSweep.sweepShift() != 0
  result.resetTimer(chSweep)



type
  SquareUnit = tuple
    frequencyTimer: int
    lengthTimer: int
    position: int

const
  SquareWavePatterns = [
    [0'u8, 0, 0, 0, 0, 0, 0, 1],  # 12.5%  _______^
    [1'u8, 0, 0, 0, 0, 0, 0, 1],  # 25%    ^______^
    [1'u8, 0, 0, 0, 0, 1, 1, 1],  # 50%    ^____^^^
    [0'u8, 1, 1, 1, 1, 1, 1, 0],  # 75%    _^^^^^^_
  ]

func squareIsLenTimerOn(frequencyH: uint8): bool =
  frequencyH.testBit(6)

func squareLength(length: uint8): int =
  length.extract(0, 5).int

func squareWavePattern(length: uint8): int =
  length.extract(6, 7).int

func squareFreq(frequencyL, frequencyH: uint8): uint16 =
  frequencyL.uint16 or (frequencyH.extract(0, 2).uint16 shl 8)

func setSquareFreq(frequencyL, frequencyH: var uint8, freq: uint16) =
  frequencyL = (freq and 0x00ff).uint8
  frequencyH = (frequencyH and 0b11111000) or ((freq shr 8) and 0b00000111).uint8

func resetFrequencyTimer(self: var SquareUnit, frequencyL, frequencyH: uint8) =
  self.frequencyTimer = (2048 - squareFreq(frequencyL, frequencyH).int) * 4

func amplitude(self: SquareUnit, length: uint8): uint8 =
  SquareWavePatterns[length.squareWavePattern()][self.position]

func lengthStep(self: var SquareUnit, frequencyH: uint8): bool =
  result = true
  if frequencyH.squareIsLenTimerOn():
    self.lengthTimer -= 1
    if self.lengthTimer == 0:
      result = false

func step(self: var SquareUnit, frequencyL, frequencyH: uint8) =
  self.frequencyTimer -= 1
  if self.frequencyTimer == 0:
    self.resetFrequencyTimer(frequencyL, frequencyH)
    self.position = (self.position + 1) mod 8

func initSquareUnit(length: uint8, frequencyL, frequencyH: uint8): SquareUnit =
  result.resetFrequencyTimer(frequencyL, frequencyH)
  result.lengthTimer = 64 - length.squareLength()
  result.position = 0



type
  ApuStateIo* = tuple
    #[ Channel 1 ]#
    ch1Sweep:      uint8  ## 0xff10  Channel 1 Sweep register (R/W) [NR10]
                          ##   bit 6-4 - Sweep Time
                          ##   bit 3   - Sweep Increase/Decrease (0=Increase, 1=Decrease)
                          ##   bit 2-0 - Number of sweep shift (n: 0-7)
    ch1Len:        uint8  ## 0xff11  Channel 1 Sound length/Wave pattern duty (R/W) [NR11]
                          ##   bit 7-6 - Wave Pattern Duty (Read/Write)
                          ##   bit 5-0 - Sound length data (Write Only) (t1: 0-63)
    ch1Envelope:   uint8  ## 0xff12  Channel 1 Volume Envelope (R/W) [NR12]
                          ##   bit 7-4 - Initial Volume of envelope (0-0Fh) (0=No Sound)
                          ##   bit 3   - Envelope Direction (0=Decrease, 1=Increase)
                          ##   bit 2-0 - Number of envelope sweep (n: 0-7) If zero, stop envelope operation.
    ch1FrequencyL: uint8  ## 0xff13  Channel 1 Frequency lo (Write Only) [NR13]
    ch1FrequencyH: uint8  ## 0xff14  Channel 1 Frequency hi (R/W) [NR14]
                          ##   bit 7   - Initial (1=Restart Sound) (W)
                          ##   bit 6   - Counter/consecutive selection (R/W)
                          ##             (1=Stop output when length in NR11 expires)
                          ##   bit 2-0 - Frequency's higher 3 bits (x) (W)

    #[ Channel 2 ]#
    unused0:       uint8  ## 0xff15
    ch2Len:        uint8  ## 0xff16  Channel 2 Sound Length/Wave Pattern Duty (R/W) [NR21]
                          ##   bit 7-6 - Wave Pattern Duty (Read/Write)
                          ##   bit 5-0 - Sound length data (Write Only) (t1: 0-63)
    ch2Envelope:   uint8  ## 0xff17  Channel 2 Volume Envelope (R/W) [NR22]
                          ##   bit 7-4 - Initial Volume of envelope (0-0Fh) (0=No Sound)
                          ##   bit 3   - Envelope Direction (0=Decrease, 1=Increase)
                          ##   bit 2-0 - Number of envelope sweep (n: 0-7) If zero, stop envelope operation.
    ch2FrequencyL: uint8  ## 0xff18  Channel 2 Frequency lo data (W) [NR23]
    ch2FrequencyH: uint8  ## 0xff19  Channel 2 Frequency hi data (R/W) [NR24]
                          ##   bit 7   - Initial (1=Restart Sound) (W)
                          ##   bit 6   - Counter/consecutive selection (R/W)
                          ##             (1=Stop output when length in NR21 expires)
                          ##   bit 2-0 - Frequency's higher 3 bits (x) (W)

    #[ Channel 3 ]#
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

    #[ Channel 4 ]#
    unused1:       uint8  ## 0xff1f
    ch4Len:        uint8  ## 0xff20  Channel 4 Sound Length (R/W) [NR41]
                          ##   Sound Length = (64-t1)*(1/256) seconds The Length value is used only if Bit 6 in NR44 is set.
                          ##     bit 5-0 - Sound length data (t1: 0-63)
    ch4Envelope:   uint8  ## 0xff21  Channel 4 Volume Envelope (R/W) [NR42]
                          ##   bit 7-4 - Initial Volume of envelope (0-0Fh) (0=No Sound)
                          ##   bit 3   - Envelope Direction (0=Decrease, 1=Increase)
                          ##   bit 2-0 - Number of envelope sweep (n: 0-7)
                          ##     Length of 1 step = n*(1/64) seconds. If zero, stop envelope operation.
    ch4Poly:       uint8  ## 0xff22  Channel 4 Polynomial Counter (R/W) [NR43]
                          ##   bit 7-4 - Shift Clock Frequency (s)
                          ##   bit 3   - Counter Step/Width (0=15 bits, 1=7 bits)
                          ##   bit 2-0 - Dividing Ratio of Frequencies (r)
    ch4Counter:    uint8  ## 0xff23  Channel 4 Counter/consecutive; Inital (R/W) [NR44]
                          ##   bit 7   - Initial (1=Restart Sound)     (Write Only)
                          ##   bit 6   - Counter/consecutive selection (Read/Write)
                          ##             (1=Stop output when length in NR41 expires)

    #[ Control registers ]#
    channelCtrl:    uint8 ## 0xff24  Channel control / ON-OFF / Volume (R/W) [NR50]
                          ##   bit 7   - Output Vin to SO2 terminal (1=Enable)
                          ##   bit 6-4 - SO2 output level (volume)  (0-7)
                          ##   bit 3   - Output Vin to SO1 terminal (1=Enable)
                          ##   bit 2-0 - SO1 output level (volume)  (0-7)
    selectionCtrl:  uint8 ## 0xff25  Selection of Sound output terminal (R/W) [NR51]
                          ##   bit 7 - Output sound 4 to SO2 terminal
                          ##   bit 6 - Output sound 3 to SO2 terminal
                          ##   bit 5 - Output sound 2 to SO2 terminal
                          ##   bit 4 - Output sound 1 to SO2 terminal
                          ##   bit 3 - Output sound 4 to SO1 terminal
                          ##   bit 2 - Output sound 3 to SO1 terminal
                          ##   bit 1 - Output sound 2 to SO1 terminal
                          ##   bit 0 - Output sound 1 to SO1 terminal
    soundCtrl:      uint8 ## 0xff26  Sound on/off [NR52]
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
    fs: uint64            ## Frame sequencer 512Hz (8192 T-cycles)
                          ##   Length ctrl: 256Hz (16384 T-cycles)
                          ##   Sweep: 128Hz (32768 T-cycles)
                          ##   Vol envelope: 64Hz (65536 T-cycles)
    lastSample: uint64
    #[ Channel 1 ]#
    ch1Square: SquareUnit
    ch1Sweep: Sweep
    ch1Envelope: Envelope
    #[ Channel 2 ]#
    ch2Square: SquareUnit
    ch2Envelope: Envelope
  
  Apu* = ref object
    mcu: Mcu
    state*: ApuState

const
  #  Step   Length Ctr  Vol Env     Sweep
  #  ---------------------------------------
  #  0      Clock       -           -
  #  1      -           -           -
  #  2      Clock       -           Clock
  #  3      -           -           -
  #  4      Clock       -           -
  #  5      -           -           -
  #  6      Clock       -           Clock
  #  7      -           Clock       -
  #  ---------------------------------------
  #  Rate   256 Hz      64 Hz       128 Hz
  LenSteps   = [1, 0, 1, 0, 1, 0, 1, 0]
  VolSteps   = [0, 0, 0, 0, 0, 0, 0, 1]
  SweepSteps = [0, 0, 1, 0, 0, 0, 1, 0]


func isOn*(self: ApuState): bool =
  self.io.soundCtrl.testBit(7)

func leftVolume(self: ApuState): uint8 =
  self.io.channelCtrl.extract(4, 6)

func rightVolume(self: ApuState): uint8 =
  self.io.channelCtrl.extract(0, 2)

func isSo1On*(self: ApuState): bool =
  self.io.channelCtrl.testBit(3)

func so1Volume*(self: ApuState): range[0..7] =
  self.io.channelCtrl.extract(0, 2)

func isSo2On*(self: ApuState): bool =
  self.io.channelCtrl.testBit(7)

func so2Volume*(self: ApuState): range[0..7] =
  self.io.channelCtrl.extract(4, 6)


func isCh1On(self: ApuState): bool =
  self.io.soundCtrl.testBit(0)

func isCh2On(self: ApuState): bool =
  self.io.soundCtrl.testBit(1)



func ch1Amplitude(self: ApuState): tuple[so1: uint8, so2: uint8] =
  let
    amplitude = self.ch1Square.amplitude(self.io.ch1Len) * self.ch1Envelope.volume
  if self.io.selectionCtrl.testBit(0):
    result.so1 = amplitude
  if self.io.selectionCtrl.testBit(4):
    result.so2 = amplitude

func ch2Amplitude(self: ApuState): tuple[so1: uint8, so2: uint8] =
  let
    amplitude = self.ch2Square.amplitude(self.io.ch2Len) * self.ch2Envelope.volume
  if self.io.selectionCtrl.testBit(1):
    result.so1 = amplitude
  if self.io.selectionCtrl.testBit(5):
    result.so2 = amplitude



const
  CyclesPerSample = 4194304 div 48000

proc step*(self: Apu, cycles: uint64) =
  if cycles - self.state.lastSample >= CyclesPerSample:
    let
      ch1Samples = if self.state.isCh1On(): self.state.ch1Amplitude() else: (so1: 0'u8, so2: 0'u8)
      ch2Samples = if self.state.isCh2On(): self.state.ch2Amplitude() else: (so1: 0'u8, so2: 0'u8)
    var
      leftSample = (ch1Samples.so2 + ch2Samples.so2) div 2 * self.state.leftVolume
      rightSample = (ch1Samples.so1 + ch2Samples.so1) div 2 * self.state.rightVolume
    discard queueAudio(2, addr leftSample, 1)
    discard queueAudio(2, addr rightSample, 1)

    self.state.lastSample = cycles
  
  if self.state.isCh1On():
    self.state.ch1Square.step(self.state.io.ch1FrequencyL, self.state.io.ch1FrequencyH)

  if self.state.isCh2On():
    self.state.ch2Square.step(self.state.io.ch2FrequencyL, self.state.io.ch2FrequencyH)

  # Increment the frame-sequencer at every 8192 T-cycles (512Hz)
  if isDivByPowerOf2(cycles, 13):
    self.state.fs += 1
    let
      step = self.state.fs mod 8

    # Length clock
    if LenSteps[step] == 1:
      if self.state.isCh1On():
        if not self.state.ch1Square.lengthStep(self.state.io.ch1FrequencyH):
          self.state.io.soundCtrl.clearBit(0)

      if self.state.isCh2On():
        if not self.state.ch2Square.lengthStep(self.state.io.ch2FrequencyH):
          self.state.io.soundCtrl.clearBit(1)
    
    # Envelope clock
    if VolSteps[step] == 1:
      if self.state.isCh1On():
        self.state.ch1Envelope.step(self.state.io.ch1Envelope)
      if self.state.isCh2On():
        self.state.ch2Envelope.step(self.state.io.ch2Envelope)
    
    # Sweep clock
    if SweepSteps[step] == 1:
      let
        (newFreq, shouldDisable, freqChanged) = self.state.ch1Sweep.step(self.state.io.ch1Sweep)
      if freqChanged:
        setSquareFreq(self.state.io.ch1FrequencyL, self.state.io.ch1FrequencyH, newFreq)
        self.state.ch1Square.resetFrequencyTimer(self.state.io.ch1FrequencyL, self.state.io.ch1FrequencyH)
      if shouldDisable:
        self.state.io.soundCtrl.clearBit(0)


proc step*(self: Apu, cycleDelta: int, cycles: uint64) =
  if not self.state.isOn:
    return

  for c in cycles-cycleDelta.uint64 ..< cycles:
    self.step(c)


proc setupMemHandler*(mcu: Mcu, self: Apu) =
  let
    ioHandler = createHandlerFor(msApu, addr self.state.io)
    ch3Handler = MemHandler(
      read: proc(address: MemAddress): uint8 =
        ioHandler.read(address),
      write: proc(address: MemAddress, value: uint8) =
        if address == 0xff19 and value.testBit(7):
          ioHandler.write(address, value)
          self.state.io.soundCtrl.setBit(1)
          self.state.ch1Square = initSquareUnit(self.state.io.ch1Len, self.state.io.ch1FrequencyL, self.state.io.ch1FrequencyH)
          self.state.ch2Envelope = initEnvelope(self.state.io.ch2Envelope)
        elif address == 0xff14 and value.testBit(7):
          ioHandler.write(address, value)
          self.state.io.soundCtrl.setBit(0)
          self.state.ch1Envelope = initEnvelope(self.state.io.ch1Envelope)
          self.state.ch1Sweep = initSweep(self.state.io.ch1Sweep, squareFreq(self.state.io.ch1FrequencyL, self.state.io.ch1FrequencyH))
          let
            (_, shouldDisable) = self.state.ch1Sweep.calcNewFreq(self.state.io.ch1Sweep)
          if shouldDisable:
            self.state.io.soundCtrl.clearBit(0)
          self.state.ch2Square = initSquareUnit(self.state.io.ch2Len, self.state.io.ch2FrequencyL, self.state.io.ch2FrequencyH)
        else:
          ioHandler.write(address, value)
    )
  mcu.setHandler(msApu, ch3Handler)
  self.mcu = mcu

proc newApu*(mcu: Mcu): Apu =
  result = Apu()
  mcu.setupMemHandler(result)
