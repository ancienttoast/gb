##[

  Audio Processing Unit
  =====================

  * `https://gbdev.io/pandocs/#sound-controller`_
  * `https://flothesof.github.io/gameboy-sounds-in-python.html`_
  * `https://github.com/Humpheh/goboy/blob/master/pkg/apu/apu.go`_
  * `https://gist.github.com/armornick/3447121`_
  * `http://emudev.de/gameboy-emulator/bleeding-ears-time-to-add-audio/`_

]##
import
  math



type
  ApuState = tuple
    # Channel 1
    ch1Sweep:      uint8  ## 0xff10  NR10 - Channel 1 Sweep register (R/W)
    ch1Len:        uint8  ## 0xff11  NR11 - Channel 1 Sound length/Wave pattern duty (R/W)
    ch1Envelope:   uint8  ## 0xff12  NR12 - Channel 1 Volume Envelope (R/W)
    ch1FrequencyL: uint8  ## 0xff13  NR13 - Channel 1 Frequency lo (Write Only)
    ch1FrequencyH: uint8  ## 0xff14  NR14 - Channel 1 Frequency hi (R/W)

    unused0:       uint8  ## 0xff15

    # Channel 2
    ch2Len:        uint8  ## 0xff16  NR21 - Channel 2 Sound Length/Wave Pattern Duty (R/W)
    ch2Envelope:   uint8  ## 0xff17  NR22 - Channel 2 Volume Envelope (R/W)
    ch2FrequencyL: uint8  ## 0xff18  NR23 - Channel 2 Frequency lo data (W)
    ch2FrequencyH: uint8  ## 0xff19  NR24 - Channel 2 Frequency hi data (R/W)

    # Channel 3
    ch3Ctr:        uint8  ## 0xff1a  NR30 - Channel 3 Sound on/off (R/W)
    ch3Len:        uint8  ## 0xff1b  NR31 - Channel 3 Sound Length
    ch3Level:      uint8  ## 0xff1c  NR32 - Channel 3 Select output level (R/W)
    ch3FrequencyL: uint8  ## 0xff1d  NR33 - Channel 3 Frequency's lower data (W)
    ch3FrequencyH: uint8  ## 0xff1e  NR34 - Channel 3 Frequency's higher data (R/W)

    unused1:       uint8  ## 0xff1f

    # Channel 4
    ch4Len:        uint8  ## 0xff20  NR41 - Channel 4 Sound Length (R/W)
                          ##   Sound Length = (64-t1)*(1/256) seconds The Length value is used only if Bit 6 in NR44 is set.
                          ##     bit 5-0 - Sound length data (t1: 0-63)
    ch4Envelope:   uint8  ## 0xff31  NR42 - Channel 4 Volume Envelope (R/W)
                          ##   bit 7-4 - Initial Volume of envelope (0-0Fh) (0=No Sound)
                          ##   bit 3   - Envelope Direction (0=Decrease, 1=Increase)
                          ##   bit 2-0 - Number of envelope sweep (n: 0-7)
                          ##     Length of 1 step = n*(1/64) seconds. If zero, stop envelope operation.

    # Control registers
    channelCtrl:    uint8 ## 0xff24  NR50 - Channel control / ON-OFF / Volume (R/W)
                          ##   bit 7   - Output Vin to SO2 terminal (1=Enable)
                          ##   bit 6-4 - SO2 output level (volume)  (0-7)
                          ##   bit 3   - Output Vin to SO1 terminal (1=Enable)
                          ##   bit 2-0 - SO1 output level (volume)  (0-7)
    selectionCtrl:  uint8 ## 0xff25  NR51 - Selection of Sound output terminal (R/W)
                          ##   bit 7 - Output sound 4 to SO2 terminal
                          ##   bit 6 - Output sound 3 to SO2 terminal
                          ##   bit 5 - Output sound 2 to SO2 terminal
                          ##   bit 4 - Output sound 1 to SO2 terminal
                          ##   bit 3 - Output sound 4 to SO1 terminal
                          ##   bit 2 - Output sound 3 to SO1 terminal
                          ##   bit 1 - Output sound 2 to SO1 terminal
                          ##   bit 0 - Output sound 1 to SO1 terminal
    soundCtrl:      uint8 ## 0xff26  NR52 - Sound on/off
                          ##   bit 7 - All sound on/off (0=stop all sound circuits) (R/W)
                          ##   bit 3 - Sound 4 ON flag (R)
                          ##   bit 2 - Sound 3 ON flag (R)
                          ##   bit 1 - Sound 2 ON flag (R)
                          ##   bit 0 - Sound 1 ON flag (R)

    unused2:        array[9, uint8]
                          ## 0xff27-0xff2f
    wav:            array[16, uint8]
                          ## 0xff30-0xff3f  Wave Pattern RAM

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
