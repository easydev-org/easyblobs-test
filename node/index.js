'use strict';

// A real module the toolchain parses and the registry stores.
function greet(name) {
  return `hello ${name}`;
}

module.exports = { greet };

if (require.main === module) {
  console.log(greet('easyblobs'));
}
