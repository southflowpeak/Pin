const raycastConfig = require("@raycast/eslint-config");

// Flatten nested arrays in raycast config (workaround for ESLint 9.x compatibility)
module.exports = raycastConfig.flat(Infinity);
