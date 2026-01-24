# S01-PROJECT-INVENTORY: simple_process

**BACKWASH DOCUMENT** - Generated retroactively from existing implementation
**Date**: 2026-01-23
**Library**: simple_process
**Status**: Production (v1.0.0, 9 tests passing)

## Project Structure

```
simple_process/
├── src/
│   ├── simple_process.e         # Main process class
│   ├── simple_async_process.e   # Async wrapper
│   └── simple_process_helper.e  # Legacy helper
├── Clib/
│   ├── simple_process.h         # C header
│   ├── simple_process.c         # C implementation
│   └── compile.bat              # Build script
├── testing/
│   ├── application.e            # Test runner
│   └── test_simple_process.e    # Test cases
├── docs/
│   ├── index.html               # API documentation
│   └── images/
│       └── logo.png
├── simple_process.ecf           # Library configuration
├── README.md                    # User documentation
├── CHANGELOG.md                 # Version history
├── LICENSE                      # MIT License
├── build.sh                     # Build script
└── roadmap.md                   # Future plans
```

## ECF Configuration

- **Library Target**: simple_process
- **Test Target**: simple_process_tests
- **External Object**: Clib/simple_process.obj
- **Dependencies**: EiffelBase

## Build Artifacts

- Clib/simple_process.obj - C compiled object
- EIFGENs/simple_process/ - Library compilation
- EIFGENs/simple_process_tests/ - Test compilation
