---
status: accepted
---

# Use Nim as the language and toolchain

Quark is a regular Nim project: programs use Nim syntax, types, and macros and compile through the Nim toolchain. Backend adapters lower Quark's explicit lattice constructs to supported systems such as QEX and Grid; Quark will not own a separate parser, general-purpose type system, or direct C/C++ code generator unless future requirements demonstrate that Nim cannot express or enforce essential semantics. This choice preserves the desired `parallel for` syntax, which Nim accepts as a macro invocation, while retaining Nim's metaprogramming and C/C++ interoperability.
