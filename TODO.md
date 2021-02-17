# TODO

* __FEATURE__: PPU test suite: <https://github.com/mattcurrie/mealybug-tearoom-tests>
* emscriten
  * __FEATURE__: investigate rom loading/savestate saving
  * __REFACTOR__: get rid of `defined(emscripten)` expression in debugger, move them to some central location ideally
  * __BUG__: sdl2 clipboard fails to compile with emscripten
  * __BUG__: std/times/DateTime fails to compile with emscripten
* _dmg_:
  * __FEATURE__: Properly handle turning off the LCD (e.g: LY = 0, ...)
    * [https://www.reddit.com/r/Gameboy/comments/a1c8h0/what_happens_when_a_gameboy_screen_is_disabled/eap4f8c?utm_source=share&utm_medium=web2x&context=3]
  * __FEATURE__: Accurate PPU interrupt handling
    * [https://github.com/TheThief/CoroGB/blob/20f809f8695daf9b3a92c6be27fdc8383bf8c495/gb_gpu.cpp#L606]
    * [http://gameboy.mongenel.com/dmg/istat98.txt]