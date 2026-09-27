using Toybox.Lang;

// Width of a string in pixel-font glyph columns (mirrors tools/gen_pixel_font.py:
// 5-wide glyphs + 1 spacing; narrow punctuation, I and space).
// Multiply by the font scale for screen pixels.
function pixelColumns(text as Lang.String) as Lang.Number {
  var chars = text.toCharArray();
  var cols = 0;
  for (var i = 0; i < chars.size(); i++) {
    var c = chars[i];
    if (c == ':' || c == '.' || c == '!' || c == '\'') {
      cols += 2;
    } else if (c == ' ' || c == ',') {
      cols += 3;
    } else if (c == 'I') {
      cols += 4;
    } else if (c == '-') {
      cols += 5;
    } else {
      cols += 6;
    }
  }
  return cols > 1 ? cols - 1 : 1;
}
