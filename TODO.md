# TODO

* __FEATURE__: PPU test suite: <https://github.com/mattcurrie/mealybug-tearoom-tests>
* emscriten
  * __FEATURE__: investigate rom loading/savestate saving
  * __REFACTOR__: get rid of `defined(emscripten)` expression in debugger, move them to some central location ideally
  * __BUG__: sdl2 clipboard fails to compile with emscripten
  * __BUG__: std/times/DateTime fails to compile with emscripten