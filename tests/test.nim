{.warning[UnusedImport]: off.}

import
  gb/common/test_util,

  # DMG
  gb/dmg/test_cpu as dmg_cpu,
  gb/dmg/test_timer as dmg_timer,
  gb/dmg/test_joypad as dmg_joypad,

  # GBA
  gb/gba/test_cpu as gba_cpu,
  gb/gba/test_mem as gba_mem,

  rom/[blargg/test_blargg, dmg_acid2/test_dmg_acid2]
