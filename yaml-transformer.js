/**
 * Metro transformer for .yaml/.yml files.
 * Converts YAML content into a JS module that exports the raw string,
 * which is then parsed by js-yaml at runtime.
 */
const upstreamTransformer = require('@react-native/metro-babel-transformer');

module.exports.transform = function ({ src, filename, options }) {
  if (filename.endsWith('.yaml') || filename.endsWith('.yml')) {
    // Export the raw YAML string as a default export
    const escaped = JSON.stringify(src);
    const code = `module.exports = ${escaped};`;
    return upstreamTransformer.transform({
      src: code,
      filename,
      options,
    });
  }
  return upstreamTransformer.transform({ src, filename, options });
};
