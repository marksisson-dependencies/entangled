{ mkDerivation, array, base, containers, dhall, directory, either
, exceptions, extra, filepath, fsnotify, Glob, hspec
, hspec-megaparsec, lib, megaparsec, monad-logger, mtl
, optparse-applicative, prettyprinter, prettyprinter-ansi-terminal
, QuickCheck, quickcheck-instances, regex-tdfa, rio, sqlite-simple
, terminal-size, text, time, transformers
}:
mkDerivation {
  pname = "entangled";
  version = "1.4.0";
  src = ./.;
  isLibrary = true;
  isExecutable = true;
  enableSeparateDataOutput = true;
  libraryHaskellDepends = [
    array base containers dhall directory either exceptions extra
    filepath fsnotify Glob megaparsec monad-logger mtl prettyprinter
    prettyprinter-ansi-terminal regex-tdfa rio sqlite-simple
    terminal-size text time transformers
  ];
  executableHaskellDepends = [
    array base containers dhall directory either exceptions extra
    filepath fsnotify Glob megaparsec monad-logger mtl
    optparse-applicative prettyprinter prettyprinter-ansi-terminal
    regex-tdfa rio sqlite-simple terminal-size text time transformers
  ];
  testHaskellDepends = [
    array base containers dhall directory either exceptions extra
    filepath fsnotify Glob hspec hspec-megaparsec megaparsec
    monad-logger mtl prettyprinter prettyprinter-ansi-terminal
    QuickCheck quickcheck-instances regex-tdfa rio sqlite-simple
    terminal-size text time transformers
  ];
  homepage = "https://entangled.github.io/";
  description = "bi-directional tangle daemon for literate programming";
  license = lib.licenses.asl20;
}
