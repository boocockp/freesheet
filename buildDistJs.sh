#!/bin/bash

mkdir -p dist

browserify -o dist/freesheet.js \
  -r ./target/coffeejs/parser/TextParser.js:text-parser \
  -r ./target/coffeejs/runtime/ReactiveRunner.js:reactive-runner \
  -r ./target/coffeejs/runtime/TextLoader.js:text-loader \
  -r ./target/coffeejs/functions/CoreFunctions.js:core-functions \
  -r ./target/coffeejs/functions/PageFunctions.js:page-functions \
  -r ./target/coffeejs/functions/TimeFunctions.js:time-functions \
  -r ./target/coffeejs/worksheet/TableWorksheet.js:table-worksheet
