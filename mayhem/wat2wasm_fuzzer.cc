// wat2wasm entry point with every WebAssembly feature enabled (as `wat2wasm --enable-all`), so the
// text parser's typed-reference paths (`(ref $t)`, `(ref null $t)`) are reachable.
#include "wabt/ir.h"
#include "wabt/wast-lexer.h"
#include "wabt/wast-parser.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  wabt::Errors lex_errors;
  std::unique_ptr<wabt::WastLexer> lexer =
      wabt::WastLexer::CreateBufferLexer("fake_file", data, size, &lex_errors);
  if (!lexer) {
    return 0;
  }

  std::unique_ptr<wabt::Module> module;
  wabt::Errors errors;
  wabt::Features features;
#define WABT_FEATURE(variable, flag, default_, help) features.enable_##variable();
#include "wabt/feature.def"
#undef WABT_FEATURE
  wabt::WastParseOptions parse_wast_options(features);
  ParseWatModule(lexer.get(), &module, &errors, &parse_wast_options);
  return 0;
}
