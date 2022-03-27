# Package

version       = "0.1"
author        = "Håvard Mjaavatten"
description   = "Marshalling library between XML and Nim structures"
license       = "MIT"
srcDir        = "src"

# Dependencies

# 1.6.0 is required for `std/times.datetime` proc used in tests.
requires "nim >= 1.6.0"
requires "result >= 0.3.0"
requires "zero_functional >= 1.2.1"
