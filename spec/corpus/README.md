# BSON corpus tests

These files come from the official MongoDB specifications repository.

Layout:

- `bson-corpus/tests/` matches `source/bson-corpus/tests/`
- `bson-binary-vector/tests/` matches `source/bson-binary-vector/tests/`

The JSON files are the same as the official files. The test runner in
`spec/spec_helper.cr` now includes the Y10K datetime case because the
library implements and provides `BSON::DateTime`.

The runner still skips `Bad DBRef` parse errors. DBRef is a driver convention,
not a BSON type. This library keeps those documents as normal documents.
